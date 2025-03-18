import os
import sys
from pathlib import Path


def check_sonar_config():
    """Перевірка налаштувань SonarCloud"""
    sonar_file = Path("sonar-project.properties")
    if not sonar_file.exists():
        print("❌ Відсутній файл sonar-project.properties")
        return False

    required_props = ["sonar.projectKey", "sonar.organization", "sonar.sources"]

    with open(sonar_file) as f:
        content = f.read()
        for prop in required_props:
            if prop not in content:
                print(f"❌ Відсутня властивість {prop} в sonar-project.properties")
                return False

    return True


def check_snyk_config():
    """Перевірка налаштувань Snyk"""
    snyk_file = Path(".snyk")
    if not snyk_file.exists():
        print("❌ Відсутній файл .snyk")
        return False

    github_token = os.getenv("SNYK_TOKEN")
    if not github_token:
        print("⚠️ Не налаштована змінна оточення SNYK_TOKEN")
        return False

    return True


def check_security_tokens():
    """Перевірка наявності токенів безпеки"""
    required_tokens = ["SONAR_TOKEN", "SNYK_TOKEN", "GITHUB_TOKEN"]

    missing_tokens = [token for token in required_tokens if not os.getenv(token)]

    if missing_tokens:
        print(f"❌ Відсутні необхідні токени: {', '.join(missing_tokens)}")
        return False
    return True


def check_security_files():
    """Перевірка наявності файлів безпеки"""
    required_files = {
        ".snyk": "Конфігурація Snyk",
        "sonar-project.properties": "Конфігурація SonarCloud",
        ".github/workflows/ci.yml": "CI/CD конфігурація",
    }

    for file_path, description in required_files.items():
        if not Path(file_path).exists():
            print(f"❌ Відсутній {description}: {file_path}")
            return False
    return True


def main():
    print("🔍 Перевірка налаштувань безпеки...")

    checks = [
        ("Конфігурація SonarCloud", check_sonar_config()),
        ("Конфігурація Snyk", check_snyk_config()),
        ("Токени безпеки", check_security_tokens()),
        ("Файли безпеки", check_security_files()),
    ]

    success = all(result for _, result in checks)
    failed = [name for name, result in checks if not result]

    if success:
        print("\n✅ Всі перевірки безпеки пройдені успішно!")
    else:
        print(f"\n❌ Провалені перевірки: {', '.join(failed)}")
        sys.exit(1)


if __name__ == "__main__":
    main()
