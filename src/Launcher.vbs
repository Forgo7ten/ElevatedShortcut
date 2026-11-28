Option Explicit

Dim shell, fso, root, mode, createMode, task, engine, scriptPath, command, result, id, payload, i
Set shell = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")
root = fso.GetParentFolderName(WScript.ScriptFullName)

If WScript.Arguments.Count < 1 Then WScript.Quit 2
mode = LCase(WScript.Arguments.Item(0))

If mode = "fixed" Then
    If WScript.Arguments.Count <> 2 Then WScript.Quit 2
    id = WScript.Arguments.Item(1)
    If Not IsHex24(id) Then WScript.Quit 2
    Set task = FindFixedTask(id)
    If task Is Nothing Then
        MsgBox MsgTaskNotFound(), vbExclamation, "ElevatedShortcut"
        WScript.Quit 3
    End If
    On Error Resume Next
    task.Run Empty
    If Err.Number <> 0 Then
        MsgBox MsgLaunchFailed() & Err.Description, vbExclamation, "ElevatedShortcut"
        WScript.Quit 1
    End If
    On Error GoTo 0
    WScript.Quit 0
ElseIf mode = "create" Then
    If WScript.Arguments.Count < 2 Then WScript.Quit 2
    createMode = NormalizeCreateMode(WScript.Arguments.Item(1))
    If createMode = "" Then WScript.Quit 2
    If WScript.Arguments.Count < 3 Then
        MsgBox MsgSelectSource(), vbInformation, "ElevatedShortcut"
        WScript.Quit 2
    End If
    scriptPath = fso.BuildPath(root, "New-ElevatedShortcut.ps1")
    engine = SelectEngine(root)
    command = Q(engine) & " -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File " & Q(scriptPath) & " -Mode " & createMode
    For i = 2 To WScript.Arguments.Count - 1
        If InStr(WScript.Arguments.Item(i), Chr(34)) > 0 Then WScript.Quit 2
        command = command & " " & Q(WScript.Arguments.Item(i))
    Next
ElseIf mode = "register" Then
    If WScript.Arguments.Count <> 2 Then WScript.Quit 2
    payload = WScript.Arguments.Item(1)
    If Not IsBase64(payload) Then WScript.Quit 2
    scriptPath = fso.BuildPath(root, "Register-FixedTask.ps1")
    engine = SelectEngine(root)
    command = Q(engine) & " -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File " & Q(scriptPath) & " -SpecBase64 " & payload
ElseIf mode = "generic" Or mode = "worker" Then
    If mode = "generic" Then
        If WScript.Arguments.Count <> 2 Then WScript.Quit 2
        id = WScript.Arguments.Item(1)
        If Not IsHex24(id) Then WScript.Quit 2
        scriptPath = fso.BuildPath(root, "Invoke-Generic.ps1")
    Else
        If WScript.Arguments.Count <> 1 Then WScript.Quit 2
        scriptPath = fso.BuildPath(root, "GenericWorker.ps1")
    End If
    engine = SelectEngine(root)
    command = Q(engine) & " -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File " & Q(scriptPath)
    If mode = "generic" Then command = command & " -ProfileId " & id
Else
    WScript.Quit 2
End If

On Error Resume Next
result = shell.Run(command, 0, True)
If Err.Number <> 0 Then
    If mode <> "worker" And mode <> "register" Then
        MsgBox MsgLaunchFailed() & Err.Description, vbExclamation, "ElevatedShortcut"
    End If
    WScript.Quit 1
End If
On Error GoTo 0
If result <> 0 And mode = "generic" Then
    MsgBox MsgErrorCode(result), vbExclamation, "ElevatedShortcut"
End If
WScript.Quit result

Function Q(value)
    Q = Chr(34) & value & Chr(34)
End Function

Function NormalizeCreateMode(value)
    Dim lowerValue
    lowerValue = LCase(value)
    If lowerValue = "fixed" Then
        NormalizeCreateMode = "Fixed"
    ElseIf lowerValue = "generic" Then
        NormalizeCreateMode = "Generic"
    Else
        NormalizeCreateMode = ""
    End If
End Function

Function IsHex24(value)
    Dim re
    Set re = New RegExp
    re.Pattern = "^[0-9a-f]{24}$"
    re.IgnoreCase = False
    IsHex24 = re.Test(value)
End Function

Function IsBase64(value)
    Dim re
    Set re = New RegExp
    re.Pattern = "^[A-Za-z0-9+/=]+$"
    re.IgnoreCase = False
    IsBase64 = re.Test(value)
End Function

' Keep Launcher.vbs pure ASCII for wscript.exe compatibility across all Windows
' system locales while rendering native UTF-16 Chinese prompt text via ChrW.
Function U(hexCodes)
    Dim parts, item, text
    parts = Split(hexCodes, " ")
    text = ""
    For Each item In parts
        If Len(item) > 0 Then text = text & ChrW(CLng("&H0" & item))
    Next
    U = text
End Function

Function MsgTaskNotFound()
    MsgTaskNotFound = U("672A 627E 5230 6B64 5FEB 6377 65B9 5F0F 5BF9 5E94 7684 6388 6743 8BA1 5212 4EFB 52A1 FF08 53EF 80FD 5DF2 88AB 5220 9664 FF09 3002") & _
        vbCrLf & U("8BF7 5220 9664 6B64 5FEB 6377 65B9 5F0F FF0C 6216 5BF9 539F 7A0B 5E8F 91CD 65B0 6267 884C 300C 53D1 9001 5230") & _
        " -> Create Admin LNK" & U("300D 3002")
End Function

Function MsgSelectSource()
    MsgSelectSource = U("8BF7 53F3 952E 70B9 51FB") & " EXE " & U("6216") & " LNK " & _
        U("6587 4EF6 FF0C 901A 8FC7 300C 53D1 9001 5230") & " -> Create Admin LNK" & U("300D 4F7F 7528 3002")
End Function

Function MsgLaunchFailed()
    MsgLaunchFailed = U("542F 52A8") & " ElevatedShortcut " & U("5931 8D25 FF1A")
End Function

Function MsgErrorCode(code)
    MsgErrorCode = "ElevatedShortcut " & U("6267 884C 5931 8D25 FF08 9519 8BEF 7801") & " " & CStr(code) & _
        U("FF09 FF0C 8BF7 68C0 67E5 8BA1 5212 4EFB 52A1 72B6 6001 3002")
End Function

Function SelectEngine(dir)
    Dim configured, reader, fallback
    configured = fso.BuildPath(dir, "EnginePath.txt")
    If fso.FileExists(configured) Then
        Set reader = fso.OpenTextFile(configured, 1, False, -1)
        SelectEngine = Trim(reader.ReadAll)
        reader.Close
        If fso.FileExists(SelectEngine) Then Exit Function
    End If
    fallback = shell.ExpandEnvironmentStrings("%SystemRoot%") & "\System32\WindowsPowerShell\v1.0\powershell.exe"
    SelectEngine = fallback
End Function

Function FindFixedTask(id)
    Dim service, folder, tasks, task, i, candidate
    Set FindFixedTask = Nothing
    On Error Resume Next
    Set service = CreateObject("Schedule.Service")
    service.Connect
    If Err.Number <> 0 Then
        Err.Clear
        On Error GoTo 0
        Exit Function
    End If
    Set folder = service.GetFolder("\ElevatedShortcut")
    If Err.Number <> 0 Then
        Err.Clear
        On Error GoTo 0
        Exit Function
    End If
    Set tasks = folder.GetTasks(1)
    If Err.Number <> 0 Then
        Err.Clear
        On Error GoTo 0
        Exit Function
    End If

    ' Task names use Run-<executable>-<ID>. Match by the stable ID suffix
    ' carried by managed shortcuts.
    For i = 1 To tasks.Count
        Set task = tasks.Item(i)
        candidate = CStr(task.Name)
        If Left(candidate, 4) = "Run-" And Right(candidate, 25) = "-" & id Then
            If IsFixedTaskIdentity(task, id) Then
                Set FindFixedTask = task
                Exit For
            End If
        End If
    Next
    On Error GoTo 0
End Function

Function IsFixedTaskIdentity(task, id)
    Dim description, marker, nextChars
    IsFixedTaskIdentity = False
    On Error Resume Next
    description = CStr(task.Definition.RegistrationInfo.Description)
    If Err.Number <> 0 Then
        Err.Clear
        Exit Function
    End If
    On Error GoTo 0
    marker = "ElevatedShortcut:" & id
    If Left(description, Len(marker)) <> marker Then Exit Function
    If Len(description) = Len(marker) Then
        IsFixedTaskIdentity = True
        Exit Function
    End If
    nextChars = Mid(description, Len(marker) + 1, 2)
    IsFixedTaskIdentity = (nextChars = vbCrLf Or Left(nextChars, 1) = vbLf)
End Function
