import os
import sys
import yaml
from pathlib import Path
import requests


def check_workflow_files():
    """Перевірка наявності та валідності файлів GitHub Actions"""
    workflows_dir = Path(".github/workflows")

    if not workflows_dir.exists():
        print("❌ Директорія .github/workflows відсутня")
        return False

    required_files = ["ci.yml", "deploy.yml"]
    found_files = [f.name for f in workflows_dir.glob("*.yml")]

    if not all(f in found_files for f in required_files):
        print(f"❌ Відсутні необхідні файли: {set(required_files) - set(found_files)}")
        return False

    # Перевіряємо валідність YAML
    for file in required_files:
        try:
            with open(workflows_dir / file) as f:
                yaml.safe_load(f)
        except Exception as e:
            print(f"❌ Помилка в {file}: {str(e)}")
            return False

    print("✅ Файли GitHub Actions в порядку")
    return True


def check_actions_status():
    """Перевірка статусу GitHub Actions"""
    token = os.getenv("GITHUB_TOKEN")
    repo = os.getenv("GITHUB_REPOSITORY", "your-org/predator-analytics")

    if not token:
        print("❌ Відсутній GITHUB_TOKEN")
        return False

    try:
        headers = {"Authorization": f"token {token}", "Accept": "application/vnd.github.v3+json"}
        response = requests.get(
            f"https://api.github.com/repos/{repo}/actions/runs", headers=headers
        )

        if response.status_code == 200:
            runs = response.json()["workflow_runs"]
            if runs:
                latest = runs[0]
                status = "✅" if latest["conclusion"] == "success" else "❌"
                print(f"{status} Останній запуск: {latest['conclusion']}")
                return latest["conclusion"] == "success"
        return False
    except Exception as e:
        print(f"❌ Помилка при перевірці статусу: {str(e)}")
        return False


def check_dependencies():
    """Перевірка наявності необхідних залежностей"""
    required_files = ["requirements.txt", "Dockerfile", "docker-compose.yml"]

    for file in required_files:
        if not Path(file).exists():
            print(f"❌ Відсутній файл {file}")
            return False

    print("✅ Всі необхідні файли присутні")
    return True


def main():
    print("🔍 Перевірка налаштувань GitHub Actions...")

    checks = [
        ("Файли конфігурації", check_workflow_files()),
        ("Статус Actions", check_actions_status()),
        ("Залежності", check_dependencies()),
    ]

    success = all(check[1] for check in checks)

    if success:
        print("\n✅ Всі перевірки пройдені успішно!")
        sys.exit(0)
    else:
        print("\n❌ Знайдено проблеми, які потребують виправлення")
        sys.exit(1)


if __name__ == "__main__":
    main()
