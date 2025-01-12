# frozen_string_literal: true

require "decidim/components/namer"

Decidim.register_component(:accountability) do |component|
  component.engine = Decidim::Accountability::Engine
  component.admin_engine = Decidim::Accountability::AdminEngine
  component.icon = "media/images/decidim_accountability.svg"
  component.stylesheet = "decidim/accountability/accountability"
  component.permissions_class_name = "Decidim::Accountability::Permissions"
  component.query_type = "Decidim::Accountability::AccountabilityType"

  component.on(:before_destroy) do |instance|
    raise StandardError, "Can't remove this component" if Decidim::Accountability::Result.where(component: instance).any?
  end

  # These actions permissions can be configured in the admin panel
  component.actions = %w(comment)

  component.register_resource(:result) do |resource|
    resource.model_class_name = "Decidim::Accountability::Result"
    resource.template = "decidim/accountability/results/linked_results"
    resource.card = "decidim/accountability/result"
    resource.searchable = false
    resource.actions = %w(comment)
  end

  component.settings(:global) do |settings|
    settings.attribute :scopes_enabled, type: :boolean, default: true
    settings.attribute :scope_id, type: :scope
    settings.attribute :comments_enabled, type: :boolean, default: true
    settings.attribute :comments_max_length, type: :integer, required: false
    settings.attribute :intro, type: :text, translated: true, editor: true
    settings.attribute :categories_label, type: :string, translated: true, editor: true
    settings.attribute :subcategories_label, type: :string, translated: true, editor: true
    settings.attribute :heading_parent_level_results, type: :string, translated: true, editor: true
    settings.attribute :heading_leaf_level_results, type: :string, translated: true, editor: true
    settings.attribute :display_progress_enabled, type: :boolean, default: true
  end

  component.register_stat :results_count, primary: true, priority: Decidim::StatsRegistry::HIGH_PRIORITY do |components, _start_at, _end_at|
    Decidim::Accountability::Result.where(component: components).count
  end

  component.settings(:step) do |settings|
    settings.attribute :comments_blocked, type: :boolean, default: false
  end

  component.exports :results do |exports|
    exports.collection do |component_instance|
      Decidim::Accountability::Result
        .where(component: component_instance)
        .includes(:category, :scope, :status, component: { participatory_space: :organization })
    end

    exports.include_in_open_data = true

    exports.serializer Decidim::Accountability::ResultSerializer
  end

  component.exports :result_comments do |exports|
    exports.collection do |component_instance|
      Decidim::Comments::Export.comments_for_resource(
        Decidim::Accountability::Result, component_instance
      ).includes(:author, :root_commentable, :commentable)
    end

    exports.include_in_open_data = true

    exports.serializer Decidim::Comments::CommentSerializer
  end

  component.seeds do |participatory_space|
    admin_user = Decidim::User.find_by(
      organization: participatory_space.organization,
      email: "admin@example.org"
    )

    params = {
      name: Decidim::Components::Namer.new(participatory_space.organization.available_locales, :accountability).i18n_name,
      manifest_name: :accountability,
      published_at: Time.current,
      participatory_space:,
      settings: {
        intro: Decidim::Faker::Localized.wrapped("<p>", "</p>") { Decidim::Faker::Localized.sentence(word_count: 4) },
        categories_label: Decidim::Faker::Localized.word,
        subcategories_label: Decidim::Faker::Localized.word,
        heading_parent_level_results: Decidim::Faker::Localized.word,
        heading_leaf_level_results: Decidim::Faker::Localized.word,
        scopes_enabled: true,
        scope_id: participatory_space.scope&.id
      }
    }

    component = Decidim.traceability.perform_action!("publish", Decidim::Component, admin_user, visibility: "all") do
      Decidim::Component.create!(params)
    end

    5.times do |i|
      Decidim::Accountability::Status.create!(
        component:,
        name: Decidim::Faker::Localized.word,
        key: "status_#{i}"
      )
    end

    3.times do
      parent_category = participatory_space.categories.sample
      categories = [parent_category]

      2.times do
        categories << Decidim::Category.create!(
          name: Decidim::Faker::Localized.sentence(word_count: 5),
          description: Decidim::Faker::Localized.wrapped("<p>", "</p>") do
            Decidim::Faker::Localized.paragraph(sentence_count: 3)
          end,
          parent: parent_category,
          participatory_space:
        )
      end

      categories.each do |category|
        result = Decidim.traceability.create!(
          Decidim::Accountability::Result,
          admin_user,
          {
            component:,
            scope: participatory_space.organization.scopes.sample,
            category:,
            title: Decidim::Faker::Localized.sentence(word_count: 2),
            description: Decidim::Faker::Localized.wrapped("<p>", "</p>") do
              Decidim::Faker::Localized.paragraph(sentence_count: 3)
            end
          },
          visibility: "all"
        )

        Decidim::Comments::Seed.comments_for(result)

        3.times do
          child_result = Decidim.traceability.create!(
            Decidim::Accountability::Result,
            admin_user,
            {
              component:,
              parent: result,
              start_date: Time.zone.today,
              end_date: Time.zone.today + 10,
              status: Decidim::Accountability::Status.all.sample,
              progress: rand(1..100),
              title: Decidim::Faker::Localized.sentence(word_count: 2),
              description: Decidim::Faker::Localized.wrapped("<p>", "</p>") do
                Decidim::Faker::Localized.paragraph(sentence_count: 3)
              end
            },
            visibility: "all"
          )

          rand(0..5).times do |i|
            child_result.timeline_entries.create!(
              entry_date: child_result.start_date + i.days,
              title: Decidim::Faker::Localized.sentence(word_count: 2),
              description: Decidim::Faker::Localized.paragraph(sentence_count: 1)
            )
          end

          Decidim::Comments::Seed.comments_for(child_result)
        end
      end
    end
  end
end
