# frozen_string_literal: true

require "test_helper"

class GuideTest < JM::TestCase
  def test_guide_prints_agent_guide_without_init
    # No `jm init` here: the guide must work in a fresh environment.
    code, out, _err = run_cli("guide")
    assert_equal 0, code
    assert_match(/coding agent 向けガイド/, out)
    assert_match(/JM_AUTHOR/, out)
  end

  def test_guide_prints_even_with_json_flag
    code, out, _err = run_cli("guide", "--json")
    assert_equal 0, code
    refute_empty out
  end
end
