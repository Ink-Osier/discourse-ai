# frozen_string_literal: true

module DiscourseAi
  module Summarization
    class EntryPoint
      def inject_into(plugin)
        plugin.add_to_serializer(:current_user, :can_summarize) do
          return false if !SiteSetting.ai_summarization_enabled
          scope.user.in_any_groups?(SiteSetting.ai_custom_summarization_allowed_groups_map)
        end

        plugin.add_to_serializer(:topic_view, :summarizable) do
          scope.can_see_summary?(object.topic)
        end

        plugin.add_to_serializer(:web_hook_topic_view, :summarizable) do
          scope.can_see_summary?(object.topic)
        end

        # Don't add gists to the following topic lists.
        gist_skipped_lists = %i[suggested semantic_related]

        plugin.register_modifier(:topic_query_create_list_topics) do |topics, options|
          if SiteSetting.ai_summarization_enabled && SiteSetting.ai_summary_gists_enabled &&
               !gist_skipped_lists.include?(options[:filter])
            topics.includes(:ai_gist_summary)
          else
            topics
          end
        end

        plugin.add_to_serializer(
          :topic_list_item,
          :ai_topic_gist,
          include_condition: -> { scope.can_see_gists? },
        ) do
          return if gist_skipped_lists.include?(options[:filter])
          object.ai_gist_summary&.summarized_text
        end

        # As this event can be triggered quite often, let's be overly cautious enqueueing
        # jobs if the feature is disabled.
        plugin.on(:post_created) do |post|
          if SiteSetting.discourse_ai_enabled && SiteSetting.ai_summarization_enabled &&
               SiteSetting.ai_summary_gists_enabled && post.topic
            Jobs.enqueue(:fast_track_topic_gist, topic_id: post&.topic_id)
          end
        end
      end
    end
  end
end
