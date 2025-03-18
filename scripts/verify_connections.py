import os
import sys
import requests
import subprocess
from pathlib import Path


def check_sonarqube():
    """Перевірка SonarQube"""
    try:
        token = "ae5fe5168d12c610c7b94cdb641b53e1c54c0654"
        host = "http://localhost:9000"
        response = requests.get(
            f"{host}/api/system/status", auth=(token, ""), timeout=10, verify=True
        )

        if response.status_code == 200:
            print("✅ SonarQube: З'єднання успішне")
            return True
        print(f"❌ SonarQube: Помилка з'єднання ({response.status_code})")
        return False
    except Exception as e:
        print(f"❌ SonarQube: {str(e)}")
        return False


def check_sonar_scanner():
    """Перевірка SonarScanner"""
    try:
        result = subprocess.run(["sonar-scanner", "-v"], capture_output=True, text=True)
        if result.returncode == 0:
            print("✅ SonarScanner: Встановлено")
            return True
        print("❌ SonarScanner: Не встановлено")
        return False
    except Exception:
        print("❌ SonarScanner: Не знайдено")
        return False


def check_configs():
    """Перевірка конфігураційних файлів"""
    files = {
        "sonar-project.properties": "SonarQube конфігурація",
        ".snyk": "Snyk конфігурація",
        "docker-compose.yml": "Docker конфігурація",
        ".env": "Змінні оточення",
    }

    all_exist = True
    for file, desc in files.items():
        if Path(file).exists():
            print(f"✅ {desc}: Файл знайдено")
        else:
            print(f"❌ {desc}: Файл відсутній")
            all_exist = False
    return all_exist


def check_docker():
    """Перевірка Docker"""
    try:
        result = subprocess.run(["docker", "--version"], capture_output=True, text=True)
        if result.returncode == 0:
            print("✅ Docker: Встановлено")

            # Перевіряємо Docker Compose
            compose_result = subprocess.run(
                ["docker-compose", "--version"], capture_output=True, text=True
            )
            if compose_result.returncode == 0:
                print("✅ Docker Compose: Встановлено")
                return True
        return False
    except Exception as e:
        print(f"❌ Docker: {str(e)}")
        return False


def main():
    print("🔍 Перевірка всіх підключень...\n")

    results = [
        ("SonarQube", check_sonarqube()),
        ("SonarScanner", check_sonar_scanner()),
        ("Конфігурації", check_configs()),
        ("Docker", check_docker()),
    ]

    print("\nПідсумок:")
    success = all(result[1] for result in results)

    if success:
        print("\n✅ Всі перевірки успішні!")
        sys.exit(0)
    else:
        failed = [name for name, result in results if not result]
        print(f"\n❌ Невдалі перевірки: {', '.join(failed)}")
        sys.exit(1)


if __name__ == "__main__":
    main()
