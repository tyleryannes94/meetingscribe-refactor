import Foundation

/// Self-contained mobile HTML for the iPhone input form (Phase 7-B). No
/// external assets — everything (styles, the base64 photo shim) is inline so
/// the page renders offline on the phone the moment the server responds.
extension iPhoneInputService {

    nonisolated static let formHTML = """
    <!DOCTYPE html>
    <html lang="en">
    <head>
      <meta charset="utf-8">
      <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1">
      <title>Add to MeetingScribe</title>
      <style>
        :root { color-scheme: dark; }
        * { box-sizing: border-box; }
        body {
          font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
          margin: 0; padding: 20px;
          background: #0d1320; color: #e8edf7;
        }
        h1 { font-size: 22px; margin: 6px 0 2px; }
        p.sub { color: #93a4c8; margin: 0 0 18px; font-size: 14px; }
        label { display: block; font-size: 13px; color: #aab6d6; margin: 14px 0 5px; }
        input, textarea {
          width: 100%; padding: 12px; font-size: 16px;
          border-radius: 10px; border: 1px solid #2a3550;
          background: #121a2c; color: #e8edf7;
        }
        textarea { min-height: 80px; resize: vertical; }
        .req::after { content: " *"; color: #f97373; }
        button {
          margin-top: 22px; width: 100%; padding: 15px;
          font-size: 17px; font-weight: 600;
          border: none; border-radius: 12px;
          background: #7F56D9; color: white;
        }
        button:active { background: #6941c6; }
        .hint { font-size: 12px; color: #6b7aa0; margin-top: 4px; }
      </style>
    </head>
    <body>
      <h1>Add a Person</h1>
      <p class="sub">This goes straight into MeetingScribe on your Mac.</p>
      <form id="f" method="POST" action="/add-person">
        <label class="req">Name</label>
        <input name="name" required autocomplete="name" placeholder="Jane Doe">
        <label>Role / Title</label>
        <input name="role" placeholder="Head of Product">
        <label>Company</label>
        <input name="company" placeholder="Acme Inc.">
        <label>Email</label>
        <input name="email" type="email" inputmode="email" autocomplete="email" placeholder="jane@acme.com">
        <label>Phone</label>
        <input name="phone" type="tel" inputmode="tel" placeholder="+1 555 123 4567">
        <label>Tags</label>
        <input name="tags" placeholder="customer, conference 2026">
        <div class="hint">Comma-separated. Reuses or creates people tags.</div>
        <label>Notes</label>
        <textarea name="notes" placeholder="Where you met, what to remember…"></textarea>
        <label>Photo</label>
        <input id="photoFile" type="file" accept="image/*" capture="environment">
        <input type="hidden" name="photo" id="photo">
        <button type="submit">Add to MeetingScribe</button>
      </form>
      <script>
        const fileInput = document.getElementById('photoFile');
        const hidden = document.getElementById('photo');
        fileInput.addEventListener('change', e => {
          const file = e.target.files[0];
          if (!file) { hidden.value = ''; return; }
          const reader = new FileReader();
          reader.onload = () => { hidden.value = reader.result; };
          reader.readAsDataURL(file);
        });
      </script>
    </body>
    </html>
    """

    nonisolated static func confirmationHTML(name: String) -> String {
        let safe = name.isEmpty ? "Person"
            : name.replacingOccurrences(of: "<", with: "&lt;")
                  .replacingOccurrences(of: ">", with: "&gt;")
        let title = name.isEmpty ? "Nothing to add" : "\(safe) added to MeetingScribe ✓"
        let body = name.isEmpty
            ? "We didn't get a name — go back and try again."
            : "You can close this page, or add another."
        return """
        <!DOCTYPE html>
        <html lang="en">
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <title>Added</title>
          <style>
            :root { color-scheme: dark; }
            body {
              font-family: -apple-system, BlinkMacSystemFont, sans-serif;
              margin: 0; min-height: 100vh; display: flex; flex-direction: column;
              align-items: center; justify-content: center; text-align: center;
              background: #0d1320; color: #e8edf7; padding: 24px;
            }
            .check { font-size: 56px; }
            h1 { font-size: 22px; margin: 12px 0 6px; }
            p { color: #93a4c8; }
            a {
              margin-top: 24px; display: inline-block; padding: 13px 22px;
              background: #7F56D9; color: white; border-radius: 12px;
              text-decoration: none; font-weight: 600;
            }
          </style>
        </head>
        <body>
          <div class="check">\(name.isEmpty ? "⚠️" : "✅")</div>
          <h1>\(title)</h1>
          <p>\(body)</p>
          <a href="/add-person">Add another</a>
        </body>
        </html>
        """
    }
}
