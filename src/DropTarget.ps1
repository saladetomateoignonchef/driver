# =============================================================================
#  DropTarget.ps1 - Glisser-déposer dans une fenêtre lancée en administrateur
#                   + barre de titre aux couleurs de l'application (Windows 11)
#
#  Problème : Windows (UIPI) bloque le glisser-déposer depuis l'Explorateur
#  (droits normaux) vers une application administrateur. Le glisser-déposer
#  classique (OLE / AllowDrop) ne fonctionne donc pas ici.
#  Solution : on retire la cible OLE (RevokeDragDrop), on autorise explicitement
#  les messages WM_DROPFILES / WM_COPYDATA avec ChangeWindowMessageFilterEx, puis
#  on reçoit les fichiers via DragAcceptFiles / DragQueryFile (API shell32).
# =============================================================================

Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Xaml

if (-not ('DriverDropHook' -as [type])) {
    $refs = @(
        [System.Windows.Interop.HwndSource].Assembly.Location,      # PresentationCore
        [System.Windows.Threading.Dispatcher].Assembly.Location,    # WindowsBase
        [System.Xaml.XamlReader].Assembly.Location                   # System.Xaml
    )
    Add-Type -ReferencedAssemblies $refs -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
using System.Text;
using System.Windows.Interop;

public class DriverFileDropEventArgs : EventArgs {
    public string[] Files;
    public DriverFileDropEventArgs(string[] files) { Files = files; }
}

public class DriverDropHook {
    const int  WM_DROPFILES      = 0x0233;
    const uint WM_COPYDATA       = 0x004A;
    const uint WM_COPYGLOBALDATA = 0x0049;
    const uint MSGFLT_ALLOW      = 1;

    [DllImport("user32.dll", SetLastError = true)]
    static extern bool ChangeWindowMessageFilterEx(IntPtr hWnd, uint msg, uint action, IntPtr changeInfo);
    [DllImport("shell32.dll")]
    static extern void DragAcceptFiles(IntPtr hWnd, bool accept);
    [DllImport("shell32.dll", CharSet = CharSet.Unicode)]
    static extern uint DragQueryFile(IntPtr hDrop, uint index, StringBuilder file, uint size);
    [DllImport("shell32.dll")]
    static extern void DragFinish(IntPtr hDrop);
    [DllImport("ole32.dll")]
    static extern int RevokeDragDrop(IntPtr hWnd);

    public event EventHandler<DriverFileDropEventArgs> FilesDropped;
    HwndSourceHook hook;   // garde une référence (sinon le ramasse-miettes la supprime)

    public DriverDropHook(IntPtr hwnd) {
        RevokeDragDrop(hwnd);
        ChangeWindowMessageFilterEx(hwnd, (uint)WM_DROPFILES, MSGFLT_ALLOW, IntPtr.Zero);
        ChangeWindowMessageFilterEx(hwnd, WM_COPYDATA, MSGFLT_ALLOW, IntPtr.Zero);
        ChangeWindowMessageFilterEx(hwnd, WM_COPYGLOBALDATA, MSGFLT_ALLOW, IntPtr.Zero);
        DragAcceptFiles(hwnd, true);
        hook = new HwndSourceHook(WndProc);
        HwndSource.FromHwnd(hwnd).AddHook(hook);
    }

    IntPtr WndProc(IntPtr hwnd, int msg, IntPtr wParam, IntPtr lParam, ref bool handled) {
        if (msg == WM_DROPFILES) {
            IntPtr hDrop = wParam;
            uint count = DragQueryFile(hDrop, 0xFFFFFFFF, null, 0);
            string[] files = new string[count];
            for (uint i = 0; i < count; i++) {
                StringBuilder sb = new StringBuilder(1024);
                DragQueryFile(hDrop, i, sb, (uint)sb.Capacity);
                files[i] = sb.ToString();
            }
            DragFinish(hDrop);
            handled = true;
            EventHandler<DriverFileDropEventArgs> h = FilesDropped;
            if (h != null) { h(this, new DriverFileDropEventArgs(files)); }
        }
        return IntPtr.Zero;
    }
}

public static class DriverWindowTheme {
    [DllImport("dwmapi.dll")]
    static extern int DwmSetWindowAttribute(IntPtr hwnd, int attr, ref int value, int size);

    // Couleur de la barre de titre (Windows 11 uniquement, ignoré ailleurs). Format 0x00BBGGRR.
    public static void SetCaption(IntPtr hwnd, int captionColor, int textColor) {
        try {
            DwmSetWindowAttribute(hwnd, 35, ref captionColor, 4);   // DWMWA_CAPTION_COLOR
            DwmSetWindowAttribute(hwnd, 36, ref textColor, 4);      // DWMWA_TEXT_COLOR
        } catch { }
    }
}
'@
}
