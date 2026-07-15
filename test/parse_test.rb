# frozen_string_literal: true

require "test_helper"

class ParseTest < JM::TestCase
  def test_at_pads_year_to_earliest_instant
    assert_equal "2026-01-01T00:00:00Z", JM::Parse.at("2026")
  end

  def test_at_pads_year_month
    assert_equal "2026-03-01T00:00:00Z", JM::Parse.at("2026-03")
  end

  def test_at_pads_full_date
    assert_equal "2026-03-20T00:00:00Z", JM::Parse.at("2026-03-20")
  end

  def test_at_accepts_full_timestamp_and_normalizes_to_utc
    assert_equal "2026-03-20T12:30:00Z", JM::Parse.at("2026-03-20T12:30:00Z")
    assert_equal "2026-03-20T03:30:00Z", JM::Parse.at("2026-03-20T12:30:00+09:00")
  end

  def test_at_rejects_invalid_month
    err = assert_raises(JM::ArgError) { JM::Parse.at("2026-13") }
    assert_match(/invalid --at/, err.message)
  end

  def test_at_rejects_garbage
    assert_raises(JM::ArgError) { JM::Parse.at("last year") }
  end

  def test_since_accepts_plain_date
    assert_equal "2026-01-01T00:00:00Z", JM::Parse.since("2026-01-01")
  end

  def test_since_accepts_coarse_date
    assert_equal "2026-01-01T00:00:00Z", JM::Parse.since("2026")
    assert_equal "2026-03-01T00:00:00Z", JM::Parse.since("2026-03")
  end

  def test_since_still_accepts_relative_duration
    now = Time.utc(2026, 7, 15, 12, 0, 0)
    assert_equal "2026-07-14T12:00:00Z", JM::Parse.since("1d", now: now)
  end

  def test_since_rejects_garbage
    err = assert_raises(JM::ArgError) { JM::Parse.since("yesterday") }
    assert_match(/invalid --since/, err.message)
  end
end
