# Known Bugs & Limitations

## Linux Desktop: Image Picker Channel Error

**Symptom:** On Linux desktop, clicking the "Bild wählen" (Choose Image) button in food/meal edit dialogs fails with:
```
PlatformException(channel-error, Unable to establish connection on channel: "dev.flutter.pigeon.file_selector_linux.FileSelectorApi.showFileChooser"., null, null)
```

**Environment:**
- Flutter `image_picker_linux` plugin v1.1.2
- Occurs even when DBus is running and xdg-desktop-portal service is active
- File managers are installed and functioning normally

**Root Cause:** Unknown. The `file_selector_linux` plugin fails to establish a DBus connection to `FileSelectorApi.showFileChooser`, despite all required services being active. This appears to be an issue with the plugin's Linux integration rather than the app code.

**Workarounds:**
1. Test image picker on **web edition** — works perfectly
2. Test on **Android/iOS** — works perfectly
3. Install missing desktop file chooser service (though doesn't always help):
   ```bash
   sudo apt install zenity  # Zenity dialog provider
   ```

**Status:** Documented. Image feature is fully implemented and works on all other platforms. Linux desktop limitation accepted.
