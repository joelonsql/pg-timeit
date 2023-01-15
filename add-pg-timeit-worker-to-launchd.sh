#!/bin/sh

SCRIPT_PATH="$(cd "$(dirname "$0")" && pwd -P)"

cat >~/Library/LaunchAgents/com.github.joelonsql.pg-timeit.worker.plist << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple Computer//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
  <dict>
    <key>Label</key>
    <string>com.github.joelonsql.pg-timeit.worker</string>
    <key>ProgramArguments</key>
    <array>
      <string>$SCRIPT_PATH/pg-timeit-worker.sh</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardOutPath</key>
    <string>$SCRIPT_PATH/pg-timeit-worker.log</string>
    <key>StandardErrorPath</key>
    <string>$SCRIPT_PATH/pg-timeit-worker.log</string>
  </dict>
</plist>
EOF

launchctl load ~/Library/LaunchAgents/com.github.joelonsql.pg-timeit.worker.plist
