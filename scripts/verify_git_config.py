import os
import sys
import subprocess
from pathlib import Path

def check_git_remote():
    """Перевірка налаштувань Git remote"""
    try:
        result = subprocess.run(
            ['git', 'remote', '-v'],
            capture_output=True,
            text=True
        )
        
        if result.returncode != 0:
            print("❌ Помилка отримання Git remote")
            return False
            
        remotes = result.stdout.strip()
        if not remotes:
            print("❌ Віддалені репозиторії не налаштовано")
            return False
            
        print("✅ Git remote налаштування:")
        print(remotes)
        return True
            
    except Exception as e:
        print(f"❌ Помилка Git: {str(e)}")
        return False

def check_github_auth():
    """Перевірка автентифікації GitHub"""
    try:
        result = subprocess.run(
            ['gh', 'auth', 'status'],
            capture_output=True,
            text=True
        )
        
        if result.returncode != 0:
            print("❌ Помилка автентифікації GitHub")
            print(result.stderr)
            return False
            
        print("✅ GitHub автентифікація активна:")
        print(result.stdout.strip())
        return True
            
    except FileNotFoundError:
        print("❌ GitHub CLI (gh) не встановлено")
        return False
    except Exception as e:
        print(f"❌ Помилка GitHub: {str(e)}")
        return False

def main():
    print("🔍 Перевірка налаштувань Git та GitHub...\n")
    
    git_ok = check_git_remote()
    gh_ok = check_github_auth()
    
    if git_ok and gh_ok:
        print("\n✅ Всі налаштування коректні")
        sys.exit(0)
    else:
        print("\n❌ Виявлено проблеми з налаштуваннями")
        sys.exit(1)

if __name__ == '__main__':
    main()
