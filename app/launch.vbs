' Starts the widget with no console window at all (also when Windows Terminal is the default terminal).
Set sh = CreateObject("WScript.Shell")
d = CreateObject("Scripting.FileSystemObject").GetParentFolderName(WScript.ScriptFullName)
sh.Run "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File """ & d & "\wallpaper.ps1""", 0, False
