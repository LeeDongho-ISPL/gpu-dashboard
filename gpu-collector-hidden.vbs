Set WshShell = CreateObject("WScript.Shell")
WshShell.Run """C:\Program Files\Git\bin\bash.exe"" -c ""cd /c/Users/ISPL/Desktop/app/gpu-dashboard && bash scripts/run_collector.sh >> /c/Users/ISPL/Desktop/app/gpu-dashboard/logs/collector.log 2>&1""", 0, False
