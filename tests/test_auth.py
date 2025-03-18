import pytest
from datetime import datetime, timedelta
from api.services.auth_service import (
    validate_password,
    get_password_hash,
    verify_password,
    calculate_next_run,
)


@pytest.mark.parametrize(
    "password,expected",
    [
        ("Short1!", False),
        ("nouppercaseordigit!", False),
        ("NOLOWERCASEORDIGIT1!", False),
        ("ValidP@ssw0rd", True),
    ],
)
def test_password_validation(password, expected):
    assert validate_password(password) == expected


def test_password_hash():
    password = "TestP@ssw0rd"
    hashed = get_password_hash(password)
    assert verify_password(password, hashed)
    assert not verify_password("wrong_password", hashed)


@pytest.mark.asyncio
async def test_schedule_calculation():
    now = datetime.utcnow()

    # Daily schedule
    schedule = {"frequency": "daily", "hour": 10, "minute": 0}
    next_run = calculate_next_run(schedule)
    assert next_run.hour == 10
    assert next_run.minute == 0
    assert next_run >= now

    # Weekly schedule
    schedule = {"frequency": "weekly", "day": 1, "hour": 10}  # Monday
    next_run = calculate_next_run(schedule)
    assert next_run.weekday() == 1
    assert next_run >= now
