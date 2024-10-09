use std assert
use ../prelude.nu weekdays

#[test]
def test_one_weekday [] {
    let expected = (weekdays 2024-10-01 2024-10-01)
    let actual = 1
    assert equal $actual $expected
}

#[test]
def test_weekdays_only [] {
    let expected = (weekdays 2024-10-07 2024-10-11)
    let actual = 5
    assert equal $actual $expected
}

#[test]
def test_one_weekendday [] {
    let expected = (weekdays 2024-10-05 2024-10-05)
    let actual = 0
    assert equal $actual $expected
}

#[test]
def test_one_weekend [] {
    let expected = (weekdays 2024-10-05 2024-10-06)
    let actual = 0
    assert equal $actual $expected
}

#[test]
def test_partial_with_weekend [] {
    let expected = (weekdays 2024-10-04 2024-10-07)
    let actual = 2
    assert equal $actual $expected
}

#[test]
def test_full_month [] {
    let expected = (weekdays 2024-10-01 2024-10-31)
    let actual = 23
    assert equal $actual $expected
}
