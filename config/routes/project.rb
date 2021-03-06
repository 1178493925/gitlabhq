require 'constraints/project_url_constrainer'

resources :projects, only: [:index, :new, :create]

draw :git_http

constraints(ProjectUrlConstrainer.new) do
  # If the route has a wildcard segment, the segment has a regex constraint,
  # the segment is potentially followed by _another_ wildcard segment, and
  # the `format` option is not set to false, we need to specify that
  # regex constraint _outside_ of `constraints: {}`.
  #
  # Otherwise, Rails will overwrite the constraint with `/.+?/`,
  # which breaks some of our wildcard routes like `/blob/*id`
  # and `/tree/*id` that depend on the negative lookahead inside
  # `Gitlab::PathRegex.full_namespace_route_regex`, which helps the router
  # determine whether a certain path segment is part of `*namespace_id`,
  # `:project_id`, or `*id`.
  #
  # See https://github.com/rails/rails/blob/v4.2.8/actionpack/lib/action_dispatch/routing/mapper.rb#L155
  scope(path: '*namespace_id',
        as: :namespace,
        namespace_id: Gitlab::PathRegex.full_namespace_route_regex) do
    scope(path: ':project_id',
          constraints: { project_id: Gitlab::PathRegex.project_route_regex },
          module: :projects,
          as: :project) do

      resources :autocomplete_sources, only: [] do
        collection do
          get 'members'
          get 'issues'
          get 'merge_requests'
          get 'labels'
          get 'milestones'
          get 'commands'
        end
      end

      #
      # Templates
      #
      get '/templates/:template_type/:key' => 'templates#show', as: :template

      resource  :avatar, only: [:show, :destroy]
      resources :commit, only: [:show], constraints: { id: /\h{7,40}/ } do
        member do
          get :branches
          get :pipelines
          post :revert
          post :cherry_pick
          get :diff_for_path
        end
      end

      resource :pages, only: [:show, :destroy] do
        resources :domains, only: [:show, :new, :create, :destroy], controller: 'pages_domains', constraints: { id: /[^\/]+/ }
      end

      resources :snippets, concerns: :awardable, constraints: { id: /\d+/ } do
        member do
          get :raw
          post :mark_as_spam
        end
      end

      resources :services, constraints: { id: /[^\/]+/ }, only: [:index, :edit, :update] do
        member do
          put :test
        end
      end

      resource :mattermost, only: [:new, :create]

      namespace :prometheus do
        get :active_metrics
      end

      resources :deploy_keys, constraints: { id: /\d+/ }, only: [:index, :new, :create, :edit, :update] do
        member do
          put :enable
          put :disable
        end
      end

      resources :forks, only: [:index, :new, :create]
      resource :import, only: [:new, :create, :show]

      resources :merge_requests, concerns: :awardable, except: [:new, :create], constraints: { id: /\d+/ } do
        member do
          get :commit_change_content
          post :merge
          post :cancel_merge_when_pipeline_succeeds
          get :pipeline_status
          get :ci_environments_status
          post :toggle_subscription
          post :remove_wip
          post :assign_related_issues

          scope constraints: { format: nil }, action: :show do
            get :commits, defaults: { tab: 'commits' }
            get :pipelines, defaults: { tab: 'pipelines' }
            get :diffs, defaults: { tab: 'diffs' }
          end

          scope constraints: { format: 'json' }, as: :json do
            get :commits
            get :pipelines
            get :diffs, to: 'merge_requests/diffs#show'
          end

          get :diff_for_path, controller: 'merge_requests/diffs'

          scope controller: 'merge_requests/conflicts' do
            get :conflicts, action: :show
            get :conflict_for_path
            post :resolve_conflicts
          end
        end

        collection do
          get :diff_for_path
          post :bulk_update
        end

        resources :discussions, only: [], constraints: { id: /\h{40}/ } do
          member do
            post :resolve
            delete :resolve, action: :unresolve
          end
        end
      end

      controller 'merge_requests/creations', path: 'merge_requests' do
        post '', action: :create, as: nil

        scope path: 'new', as: :new_merge_request do
          get '', action: :new

          scope constraints: { format: nil }, action: :new do
            get :diffs, defaults: { tab: 'diffs' }
            get :pipelines, defaults: { tab: 'pipelines' }
          end

          scope constraints: { format: 'json' }, as: :json do
            get :diffs
            get :pipelines
          end

          get :diff_for_path
          get :update_branches
          get :branch_from
          get :branch_to
        end
      end

      resources :variables, only: [:index, :show, :update, :create, :destroy]
      resources :triggers, only: [:index, :create, :edit, :update, :destroy] do
        member do
          post :take_ownership
        end
      end

      resources :pipelines, only: [:index, :new, :create, :show] do
        collection do
          resource :pipelines_settings, path: 'settings', only: [:show, :update]
          get :charts
        end

        member do
          get :stage
          post :cancel
          post :retry
          get :builds
          get :failures
          get :status
        end
      end

      resources :pipeline_schedules, except: [:show] do
        member do
          post :take_ownership
        end
      end

      resources :environments, except: [:destroy] do
        member do
          post :stop
          get :terminal
          get :metrics
          get :additional_metrics
          get '/terminal.ws/authorize', to: 'environments#terminal_websocket_authorize', constraints: { format: nil }
        end

        collection do
          get :folder, path: 'folders/*id', constraints: { format: /(html|json)/ }
        end

        resources :deployments, only: [:index] do
          member do
            get :metrics
            get :additional_metrics
          end
        end
      end

      resource :cycle_analytics, only: [:show]

      namespace :cycle_analytics do
        scope :events, controller: 'events' do
          get :issue
          get :plan
          get :code
          get :test
          get :review
          get :staging
          get :production
        end
      end

      scope '-' do
        resources :jobs, only: [:index, :show], constraints: { id: /\d+/ } do
          collection do
            post :cancel_all

            resources :artifacts, only: [] do
              collection do
                get :latest_succeeded,
                  path: '*ref_name_and_path',
                  format: false
              end
            end
          end

          member do
            get :status
            post :cancel
            post :retry
            post :play
            post :erase
            get :trace, defaults: { format: 'json' }
            get :raw
          end

          resource :artifacts, only: [] do
            get :download
            get :browse, path: 'browse(/*path)', format: false
            get :file, path: 'file/*path', format: false
            get :raw, path: 'raw/*path', format: false
            post :keep
          end
        end
      end

      draw :legacy_builds

      resources :hooks, only: [:index, :create, :edit, :update, :destroy], constraints: { id: /\d+/ } do
        member do
          get :test
        end

        resources :hook_logs, only: [:show] do
          member do
            get :retry
          end
        end
      end

      resources :container_registry, only: [:index, :destroy],
                                     controller: 'registry/repositories'

      namespace :registry do
        resources :repository, only: [] do
          resources :tags, only: [:index, :destroy],
                           constraints: { id: Gitlab::Regex.container_registry_tag_regex }
        end
      end

      resources :milestones, constraints: { id: /\d+/ } do
        member do
          put :sort_issues
          put :sort_merge_requests
          get :merge_requests
          get :participants
          get :labels
        end
      end

      resources :labels, except: [:show], constraints: { id: /\d+/ } do
        collection do
          post :generate
          post :set_priorities
        end

        member do
          post :promote
          post :toggle_subscription
          delete :remove_priority
        end
      end

      resources :issues, concerns: :awardable, constraints: { id: /\d+/ } do
        member do
          post :toggle_subscription
          post :mark_as_spam
          post :move
          get :referenced_merge_requests
          get :related_branches
          get :can_create_branch
          get :realtime_changes
          post :create_merge_request
          get :discussions, format: :json
        end
        collection do
          post  :bulk_update
        end
      end

      resources :project_members, except: [:show, :new, :edit], constraints: { id: /[a-zA-Z.\/0-9_\-#%+]+/ }, concerns: :access_requestable do
        collection do
          delete :leave

          # Used for import team
          # from another project
          get :import
          post :apply_import
        end

        member do
          post :resend_invite
        end
      end

      resources :group_links, only: [:index, :create, :update, :destroy], constraints: { id: /\d+/ }

      resources :notes, only: [:create, :destroy, :update], concerns: :awardable, constraints: { id: /\d+/ } do
        member do
          delete :delete_attachment
          post :resolve
          delete :resolve, action: :unresolve
        end
      end

      get 'noteable/:target_type/:target_id/notes' => 'notes#index', as: 'noteable_notes'

      resources :boards, only: [:index, :show, :create, :update, :destroy]

      resources :todos, only: [:create]

      resources :uploads, only: [:create] do
        collection do
          get ":secret/:filename", action: :show, as: :show, constraints: { filename: /[^\/]+/ }
        end
      end

      resources :runners, only: [:index, :edit, :update, :destroy, :show] do
        member do
          get :resume
          get :pause
        end

        collection do
          post :toggle_shared_runners
        end
      end

      resources :runner_projects, only: [:create, :destroy]
      resources :badges, only: [:index] do
        collection do
          scope '*ref', constraints: { ref: Gitlab::PathRegex.git_reference_regex } do
            constraints format: /svg/ do
              # Keep around until 10.0, see gitlab-org/gitlab-ce#35307
              get :build, to: "badges#pipeline"
              get :pipeline
              get :coverage
            end
          end
        end
      end
      namespace :settings do
        get :members, to: redirect('/%{namespace_id}/%{project_id}/project_members')
        resource :ci_cd, only: [:show], controller: 'ci_cd'
        resource :integrations, only: [:show]
        resource :repository, only: [:show], controller: :repository
      end

      # Since both wiki and repository routing contains wildcard characters
      # its preferable to keep it below all other project routes
      draw :wiki
      draw :repository
    end

    resources(:projects,
              path: '/',
              constraints: { id: Gitlab::PathRegex.project_route_regex },
              only: [:edit, :show, :update, :destroy]) do
      member do
        put :transfer
        delete :remove_fork
        post :archive
        post :unarchive
        post :housekeeping
        post :toggle_star
        post :preview_markdown
        post :export
        post :remove_export
        post :generate_new_export
        get :download_export
        get :activity
        get :refs
        put :new_issue_address
      end
    end
  end
end
