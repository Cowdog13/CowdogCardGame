# Publishing and updating on itch.io

1. Create the project on itch.io (Dashboard -> Create new project): Kind "Downloadable", pricing "No payments".
   Set Visibility to Restricted (password) or Draft while it is private. Pushing builds never changes visibility.
2. Install butler (https://itch.io/docs/butler/installing.html): download the Windows archive, unzip it to
   `C:\butler`, and add that folder to PATH (or run it from there). Check with `butler -V`.
3. Run `butler login` once; it opens the browser to authorize.
4. Unzip `CowdogCardGame-windows.zip` into a folder (for example `C:\itch\cowdog-windows`).
5. Edit `tools\push_to_itch.bat` (the `TARGET` line) and run
   `tools\push_to_itch.bat C:\itch\cowdog-windows 0.4`.
   The first push creates the "windows" channel (itch.io marks it as a Windows download); later pushes upload only
   the changes. Use a new version number each time and mention it on the page: online players must have the same build.
