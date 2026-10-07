# claude-session-sync

Bring your old **Claude Code** sessions back after you switch Claude accounts in the **Claude desktop app for Windows**. One double-click.

> Unofficial community tool. It is not made or supported by Anthropic. It relies on the app's internal, undocumented file layout, which can change in any update. Read "Limits" first.

## The problem

You switch to another Claude account on the same PC and the Code tab sidebar looks empty. Nothing was deleted:

| What | Where | Scope |
|---|---|---|
| Chat transcripts and project memory | `%USERPROFILE%\.claude\projects\` | shared by every account on this Windows user |
| The session **list** shown in the sidebar | `...\Claude\claude-code-sessions\<accountId>\<orgId>\local_*.json` | **one list per account** |

This tool copies the `local_*.json` index files from your other accounts into the account you are signed in with. It never edits or deletes an existing file.

## Use

1. Sign in to the account you want to use and open the **Code** tab once (this creates its session folder).
2. Download this repo and double-click **`Sync-Claude-Sessions.bat`** from File Explorer. Do not run it from a terminal inside the Claude app: it refuses, because it must close the app.
3. Read the `Target:` line. It must be the account you just signed in with. Type `Y` and press Enter.
4. The tool closes the Claude desktop app, backs up, copies the sessions, and reopens the app.

Switch accounts again later? Repeat the same steps. Sessions that are already there are skipped, and if nothing is new the app is not closed.

**Undo:** double-click `Undo-Sync-Claude-Sessions.bat`. It removes only the files the last run copied.

Preview without changing anything (the app can stay open):

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\sync-claude-sessions.ps1
```

Other options (`-TargetAccount`, `-SourceAccount`, `-BackupDir`, `-BackupOnly`, `-Apply`) are described at the top of the script.

## How it picks the account

It reads `lastKnownAccountUuid` from the app's `config.json` (just that one value, never the token caches next to it) and uses that account as the target. The Microsoft Store build redirects `%APPDATA%\Claude` into `%LOCALAPPDATA%\Packages\Claude_*\LocalCache\Roaming\Claude`, which only processes running inside the app can see through the old path, so the script looks in the package folder first.

## Limits (please read)

- **Tested only** on Windows 10 with the Microsoft Store build of the Claude desktop app (2.26454.0.0), in Windows PowerShell 5.1 and PowerShell 7. Other Windows or app versions, and installs that are not the Store build, are untested. The step that closes and reopens the app recognises the Store build and its bundled Claude Code binary; it may not recognise other layouts, so close the app yourself first if it prints a warning.
- Only works for accounts used on the **same Windows user** on the same PC. It does not sync across machines.
- A copied session reopens, but Claude shows a notice that earlier "thinking" belongs to another organization and cannot be reused. Claude then re-reads the session, so the first replies can be slower and cost more tokens. For very long sessions it can be cheaper to start a new session in the same project folder.
- After copying, the two accounts no longer sync titles or "last activity". Run the tool again to pull in sessions created later.
- Windows only. The script is PowerShell.

## Safety and privacy

- The tool makes no network calls and sends nothing anywhere.
- A one-click run writes a backup of `%USERPROFILE%\.claude\projects` (all your chats and memory) and of the session list to a `backup\` folder **next to the script**. That folder holds sensitive data. It is git-ignored here. If you put this tool in a synced folder (OneDrive, Dropbox), exclude `backup\` and delete it when you no longer need it.
- Copy logs go to `logs\`, also git-ignored. `Undo` reads them.

## Tiếng Việt (tóm tắt)

Khi đổi tài khoản Claude trên cùng một máy Windows, tab Code bị trống vì danh sách phiên được lưu **riêng theo tài khoản**, còn nội dung chat và memory (`%USERPROFILE%\.claude\projects`) thì dùng chung. Tool này chép file danh sách phiên từ các tài khoản khác sang tài khoản bạn đang đăng nhập.

1. Đăng nhập tài khoản muốn dùng, mở tab Code một lần.
2. Double-click `Sync-Claude-Sessions.bat` từ File Explorer (không chạy từ terminal trong app).
3. Đọc dòng `Target:` xem có đúng tài khoản không, gõ `Y`.
4. Muốn hoàn tác: double-click `Undo-Sync-Claude-Sessions.bat`.

Lưu ý: chỉ kiểm thử với bản Store của app trên Windows 10. Thư mục `backup\` chứa toàn bộ chat của bạn, đừng đưa lên GitHub hay thư mục đồng bộ đám mây.

## License

MIT, see `LICENSE`.
