import os
import sys
import requests
from pathlib import Path
import yaml


def verify_sonarqube_connection():
    """Перевірка підключення до SonarQube"""
    host = os.getenv("SONAR_HOST_URL")
    token = os.getenv("SONAR_TOKEN")

    if not all([host, token]):
        return False, "Відсутні обов'язкові змінні SONAR_HOST_URL або SONAR_TOKEN"

    try:
        # Перевірка SSL підключення
        response = requests.get(
            f"{host}/api/system/status", auth=(token, ""), timeout=10, verify=True
        )

        if response.status_code != 200:
            return False, f"Помилка підключення до SonarQube: {response.status_code}"

        info = response.json()
        return True, f"SonarQube {info.get('version')} доступний"
    except requests.exceptions.SSLError:
        return False, "Помилка SSL сертифікату"
    except Exception as e:
        return False, f"Помилка з'єднання: {str(e)}"


def verify_configurations():
    """Перевірка конфігураційних файлів"""
    required_files = {
        ".github/workflows/ci.yml": "CI конфігурація",
        ".github/workflows/deploy.yml": "Deploy конфігурація",
        "sonar-project.properties": "SonarQube конфігурація",
        ".snyk": "Snyk конфігурація",
        "requirements.txt": "Python залежності",
    }

    errors = []
    for file_path, description in required_files.items():
        if not Path(file_path).exists():
            errors.append(f"Відсутній {description} ({file_path})")

    return len(errors) == 0, errors


def verify_security_tokens():
    """Перевірка наявності токенів безпеки"""
    required_tokens = {
        "GITHUB_TOKEN": "GitHub токен",
        "SONAR_TOKEN": "SonarQube токен",
        "SNYK_TOKEN": "Snyk токен",
        "CODECOV_TOKEN": "Codecov токен",
    }

    missing = []
    for token, description in required_tokens.items():
        if not os.getenv(token):
            missing.append(f"{description} ({token})")

    return len(missing) == 0, missing


def main():
    print("🔍 Комплексна перевірка налаштувань...\n")

    # Перевірка SonarQube
    sonar_ok, sonar_msg = verify_sonarqube_connection()
    print(f"{'✅' if sonar_ok else '❌'} SonarQube: {sonar_msg}")

    # Перевірка конфігурацій
    config_ok, config_errors = verify_configurations()
    print(f"\n{'✅' if config_ok else '❌'} Конфігураційні файли:")
    if not config_ok:
        for error in config_errors:
            print(f"  - {error}")

    # Перевірка токенів
    tokens_ok, missing_tokens = verify_security_tokens()
    print(f"\n{'✅' if tokens_ok else '❌'} Токени безпеки:")
    if not tokens_ok:
        for token in missing_tokens:
            print(f"  - {token}")

    # Загальний результат
    if all([sonar_ok, config_ok, tokens_ok]):
        print("\n✅ Всі перевірки успішні!")
        sys.exit(0)
    else:
        print("\n❌ Виявлено проблеми, що потребують виправлення")
        sys.exit(1)


if __name__ == "__main__":
    main()
