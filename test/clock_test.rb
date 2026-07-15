# frozen_string_literal: true

require "test_helper"

class ClockTest < Minitest::Test
  def test_now_is_utc_iso8601_with_z
    assert_match(/\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z\z/, JM::Clock.now)
  end

  def test_fixed_width_sorts_chronologically
    a = "2026-07-15T09:00:00Z"
    b = "2026-07-15T10:00:00Z"
    assert a < b, "string comparison should match chronological order"
  end

  def test_round_trip_parse
    t = JM::Clock.now
    assert_equal t, JM::Clock.parse(t).strftime(JM::Clock::FORMAT)
  end
end
