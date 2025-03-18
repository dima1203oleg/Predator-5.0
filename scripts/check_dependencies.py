import pkg_resources
import sys


def check_dependencies():
    """Перевірка версій залежностей"""
    with open("requirements.txt") as f:
        requirements = pkg_resources.parse_requirements(f)
        for requirement in requirements:
            try:
                pkg_resources.require(str(requirement))
            except pkg_resources.VersionConflict as e:
                print(f"Конфлікт версій: {e}")
                sys.exit(1)
            except pkg_resources.DistributionNotFound as e:
                print(f"Пакет не знайдено: {e}")
                sys.exit(1)


if __name__ == "__main__":
    check_dependencies()
