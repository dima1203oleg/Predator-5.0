#!/bin/bash
set -e

echo "🔍 Перевірка залежностей..."
python scripts/check_dependencies.py

echo "🔍 Перевірка підключень..."
python scripts/verify_all_connections.py

echo "✅ Всі перевірки залежностей і підключень пройдені"

chmod +x scripts/run_deps_and_connections.sh
./scripts/run_deps_and_connections.sh
