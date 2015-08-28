#
# Copyright:: Copyright (c) 2015 Chef Software Inc.
# License:: Apache License, Version 2.0
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

require 'chef-dk/authenticated_http'
require 'chef-dk/service_exceptions'
require 'chef-dk/policyfile/undo_stack'

module ChefDK
  module PolicyfileServices
    class Undelete

      # TODO: this is for the command's banner:
      # Usage: chef undelete [undo_record_timestamp] [options]
      #
      # `chef undelete` helps you recover quickly if you've deleted a policy or
      # policy group in error.
      #
      # Note that the delete commands do not copy cookbooks that might be
      # referenced by policies. If you have cleaned the policy cookbooks after
      # the delete operation you want to reverse, `chef undelete` may not be
      # able to fully restore the previous state. The delete commands also do
      # not store access control data, so you may have to manually reapply any
      # ACL customizations you have made.

      attr_reader :ui

      attr_reader :chef_config

      attr_reader :undo_record_id

      def initialize(undo_record_id: nil, config: nil, ui: nil)
        @chef_config = config
        @ui = ui
        @undo_record_id = undo_record_id

        @http_client = nil
        @undo_stack = nil
      end

      # In addition to the #run method, this class also has #list as a public
      # entry point. This prints the list of undoable items, with descriptions.
      def list
        if undo_stack.empty?
          ui.err("Nothing to undo.")
        else
          messages = []
          undo_stack.each_with_id do |timestamp, undo_record|
            messages.unshift("#{timestamp}: #{undo_record.description}")
          end
          messages.each { |m| ui.msg(m) }
        end
      end

      def run
        if undo_record_id
          if undo_stack.has_id?(undo_record_id)
            undo_stack.delete(undo_record_id) { |undo_record| restore(undo_record) }
          else
            ui.err("No undo record with id '#{undo_record_id}' exists")
          end
        else
          undo_stack.pop { |undo_record| restore(undo_record) }
        end
      rescue => e
        raise UndeleteError.new("Failed to undelete.", e)
      end

      def undo_stack
        @undo_stack ||= Policyfile::UndoStack.new
      end

      def http_client
        @http_client ||= ChefDK::AuthenticatedHTTP.new(chef_config.chef_server_url,
                                                       signing_key_filename: chef_config.client_key,
                                                       client_name: chef_config.node_name)
      end

      private

      def restore(undo_record)
        undo_record.policy_revisions.each do |policy_info|
          rel_uri = "/policy_groups/#{policy_info.policy_group}/policies/#{policy_info.policy_name}"
          http_client.put(rel_uri, policy_info.data)
          ui.msg("Restored policy '#{policy_info.policy_name}'")
        end
        ui.msg("Restored policy group '#{undo_record.policy_groups.first}'")
      end

    end
  end
end
