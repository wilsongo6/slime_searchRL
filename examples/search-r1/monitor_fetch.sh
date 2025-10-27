  #!/bin/bash
  while true; do
      if ! pgrep -f "tool_fast_api.py" > /dev/null; then
          echo "[$(date)] Fetch service died, restarting..."
          bash /lc/data/slime_searchRL/examples/search-r1/proxy.bash
      fi
      sleep 10
  done
