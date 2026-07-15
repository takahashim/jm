# frozen_string_literal: true

require "test_helper"

class PublicIdTest < Minitest::Test
  def test_format_pads_to_six_digits
    assert_equal "JM-000042", JM::PublicId.format(42)
    assert_equal "JM-000001", JM::PublicId.format(1)
  end

  def test_format_grows_beyond_width
    assert_equal "JM-1234567", JM::PublicId.format(1_234_567)
  end

  def test_normalize_accepts_equivalent_forms
    assert_equal 42, JM::PublicId.normalize("42")
    assert_equal 42, JM::PublicId.normalize("JM-42")
    assert_equal 42, JM::PublicId.normalize("jm-42")
    assert_equal 42, JM::PublicId.normalize("JM-000042")
    assert_equal 42, JM::PublicId.normalize("  JM-42  ")
  end

  def test_normalize_rejects_garbage
    assert_raises(JM::ArgError) { JM::PublicId.normalize("abc") }
    assert_raises(JM::ArgError) { JM::PublicId.normalize("JM-") }
    assert_raises(JM::ArgError) { JM::PublicId.normalize("") }
    assert_raises(JM::ArgError) { JM::PublicId.normalize(nil) }
  end
end
