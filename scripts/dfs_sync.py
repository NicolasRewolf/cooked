"""
CLI wrapper pour dfs_common.run_sync.

Usage :
    python3 scripts/dfs_sync.py           # défaut : top 500
    python3 scripts/dfs_sync.py --limit 200
"""
from dfs_common import main

if __name__ == "__main__":
    main()
