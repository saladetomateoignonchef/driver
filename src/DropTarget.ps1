# =============================================================================
#  DropTarget.ps1 - Glisser-déposer dans une fenêtre lancée en administrateur
#
#  Problème : Windows (UIPI) bloque le glisser-déposer depuis l'Explorateur
#  (droits normaux) vers une application administrateur. Le glisser-déposer
#  classique de Windows Forms (AllowDrop) ne fonctionne donc pas ici.
#  Solution : on autorise explicitement les messages WM_DROPFILES / WM_COPYDATA
#  avec ChangeWindowMessageFilterEx, puis on reçoit les fichiers via
#  DragAcceptFiles / DragQueryFile (API shell32).
# =============================================================================

if (-not ('ElevatedDropTarget' -as [type])) {
    Add-Type -ReferencedAssemblies System.Windows.Forms -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
using System.Text;
using System.Windows.Forms;

public class FileDropEventArgs : EventArgs {
    public string[] Files;
    public FileDropEventArgs(string[] files) { Files = files; }
}

public class ElevatedDropTarget : NativeWindow {
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

    public event EventHandler<FileDropEventArgs> FilesDropped;

    public ElevatedDropTarget(Control control) {
        AssignHandle(control.Handle);
        ChangeWindowMessageFilterEx(control.Handle, (uint)WM_DROPFILES, MSGFLT_ALLOW, IntPtr.Zero);
        ChangeWindowMessageFilterEx(control.Handle, WM_COPYDATA, MSGFLT_ALLOW, IntPtr.Zero);
        ChangeWindowMessageFilterEx(control.Handle, WM_COPYGLOBALDATA, MSGFLT_ALLOW, IntPtr.Zero);
        DragAcceptFiles(control.Handle, true);
    }

    protected override void WndProc(ref Message m) {
        if (m.Msg == WM_DROPFILES) {
            IntPtr hDrop = m.WParam;
            uint count = DragQueryFile(hDrop, 0xFFFFFFFF, null, 0);
            string[] files = new string[count];
            for (uint i = 0; i < count; i++) {
                StringBuilder sb = new StringBuilder(1024);
                DragQueryFile(hDrop, i, sb, (uint)sb.Capacity);
                files[i] = sb.ToString();
            }
            DragFinish(hDrop);
            EventHandler<FileDropEventArgs> handler = FilesDropped;
            if (handler != null) { handler(this, new FileDropEventArgs(files)); }
            return;
        }
        base.WndProc(ref m);
    }
}
'@
}
