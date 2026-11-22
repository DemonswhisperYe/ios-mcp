# Postman Assets

Files:
- `ios-mcp.postman_collection.json`: collection with one dedicated request per ios-mcp tool, plus `Health`, `Initialize`, `Tools List`, and `Generic Tool Call`
- `ios-mcp.postman_environment.json`: environment variables for the device address, upload samples, and all sample arguments used by the collection
- `ios-mcp_runner_safe.json`: safe read-only runner data
- `ios-mcp_runner_all_examples.json`: full tool example data, including state-changing actions

Recommended usage:
1. Import the collection and environment into Postman.
2. Select the `ios-mcp Local` environment.
3. Set `connectionPassword` to the password saved in the device's **Settings → iOS MCP**. It is a Postman `secret` variable with an empty, non-secret default; do not export or share an environment after filling it in.
4. Start with `Health`, `Initialize`, and `Tools List`. If the device has no password yet (first install or upgrade) or the password is wrong, protected requests return `401 Unauthorized`.
5. Click the dedicated tool request you want to test directly.
6. For computer-local file uploads, set `sample_upload_file_path` and `sample_upload_filename`, then send `File Transfer / upload_file`.
7. For IPA or DEB install, send `upload_file` first, then send `App Management / install_app` with the captured `uploaded_file_path`.
8. If needed, adjust the sample environment variables before sending requests.
9. Keep `Generic Tool Call` as a fallback for ad-hoc testing or newly added tools.

Authentication:
- The collection sets collection-level HTTP Basic auth for every request: username `mcp`, password `{{connectionPassword}}`.
- Remote `/mcp`, `/upload_file`, `/download_file`, and `/health` all require those credentials. The Settings page's loopback `/health` check is the only unauthenticated health probe and is not part of this collection.
- Set or rotate the password in **Settings → iOS MCP**; it applies without restarting the service. No sample password is checked in.

Notes:
- Most requests use shared sample variables such as `sample_x`, `sample_y`, `sample_bundle_id`, and `sample_text`.
- `tool_args_json` in `Generic Tool Call` must stay as raw JSON, not a quoted string.
- `upload_file` is a plain HTTP upload endpoint, not an MCP tool call. Its successful response contains only `path`, `filename`, and `size`; the collection test script stores those as `uploaded_file_path`, `uploaded_file_name`, and `uploaded_file_size`.
- `install_app` expects an IPA or DEB path that already exists on the device. Use `upload_file` first for a computer-local file. DEB installs trigger a SpringBoard restart after dpkg succeeds.
- `uninstall_app` accepts `bundle_id` for apps or `package_id` for DEB packages. DEB removals trigger a SpringBoard restart after dpkg succeeds.
- `screenshot` returns MCP image content, not text: `result.content[0].type` is `image`, `mimeType` is `image/jpeg`, and `data` contains the base64 JPEG payload.
- Some tools are stateful or disruptive, such as `press_power`, `kill_app`, `install_app`, `uninstall_app`, `open_url`, and text input tools.
- `long_press`, `double_tap`, and `drag_and_drop` call the same HID event path as tap/swipe and may change the foreground app state. `drag_and_drop` can use `points` to drag along a path and release at the last point.
- If the device IP changes, update `baseUrl` in the environment before testing.
