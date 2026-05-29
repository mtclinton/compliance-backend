# frozen_string_literal: true

# RHINENG-18501: flag TestResults whose uploaded report is based on a
# different SSG version than the policy's tailoring. Because V2::TestResult
# writes through the `v2_test_results` view (INSTEAD OF INSERT/DELETE
# triggers over historical_test_results_v2), the column has to be threaded
# through the base table, the view, and the insert function in lockstep.
class AddMismatchedToTestResults < ActiveRecord::Migration[8.1]
  def change
    add_column :historical_test_results_v2, :mismatched, :boolean, default: false, null: false

    # Teach the INSTEAD OF INSERT function to carry `mismatched` into the base table.
    update_function :v2_test_results_insert, version: 3, revert_to_version: 2

    # scenic's update_view drops + recreates the view, which would drop its
    # triggers — so drop them first and recreate after (matches the v4/v5 idiom).
    drop_trigger :v2_test_results_delete, on: :v2_test_results, revert_to_version: 1
    drop_trigger :v2_test_results_insert, on: :v2_test_results, revert_to_version: 1
    update_view :v2_test_results, version: 6, revert_to_version: 5
    create_trigger :v2_test_results_insert, on: :v2_test_results
    create_trigger :v2_test_results_delete, on: :v2_test_results
  end
end
