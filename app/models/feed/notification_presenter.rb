class Feed
  # Encapsulates the generation of text from a Stream notification
  class NotificationPresenter
    # The base URL used when constructing links to notifications
    CLIENT_URL = 'https://kitsu.io/'.freeze

    attr_reader :activity, :user
    delegate :group, to: :activity

    # @param activity [Feed::Activity] the activity object to generate a notification for
    # @param user [User] the user from whose perspective we are viewing this notification
    def initialize(activity, user)
      @activity = activity
      @user = user
    end

    # @return [String] the full URL for the notification in the web app
    def url
      "#{CLIENT_URL}#{path}?notification=#{activity.id}"
    end

    # @return [String] the human-readable textual representation of the notification
    def message
      actor = actor.name

      case verb
      when :follow, :post_like, :comment_like, :invited
        translate(verb, actor: actor)
      when :post
        translate('mention.post', actor: actor)
      when :mention
        translate('mention.comment', actor: actor)
      when :reply
        translate("reply.#{reply_type.join('.')}", actor: actor)
      end
    end

    # @return [Symbol] the verb of the activity
    def verb
      case activity.verb
      when :comment
        if activity.mentioned_users.include?(user.id)
          :mention
        else
          :reply
        end
      else
        activity.verb.to_sym
      end
    end

    # @return [Symbol] the setting that applies to this notification
    def setting
      verb = verb.to_s
      case verb
      when /_like\z/ then :likes
      when 'invited' then :invites
      when 'media_reaction_vote' then :reaction_votes
      else verb.pluralize.to_sym
      end
    end

    # @param user [User] the user to get the setting for
    # @return [NotificationSetting] the user's setting for this notifications
    def setting_for(user)
      NotificationSetting.where(user_id: user, setting_type: setting).first
    end

    private

    # @return [String] the path to view the notification in the web app
    def path
      case subject.class
      when Post, Comment, GroupInvite then path_for(subject)
      when PostLike, CommentLike then path_for(target)
      when Follow then path_for(actor)
      end
    end

    # @param obj [ActiveRecord::Base] the object to generate a path for
    # @return [String] the path to view this in the web app
    def path_for(obj)
      type = obj.class.name.underscore.pluralize.dasherize
      id = obj.id
      "#{type}/#{id}"
    end

    # For a reply, figure out what *kind* of reply it is.  This code sucks, but we don't have a
    # better solution right now.
    #
    # @return [Array<Symbol>] the path of the translation
    def reply_type
      reply_to_user = load_ref(activity.reply_to_user)
      if target.user.id == user.id then %i[post you] # X replied to your post
      elsif reply_to_user.id == user.id then %i[comment you] # X replied to your comment
      elsif target.user.id == actor.id then %i[post themself] # X replied to their own post
      elsif target.is_a?(Post) then %i[post author] # X replied to Y's post
      else %i[post unknown]
      end
    end

    # Split a Stream-style reference string
    # @return [Array<String,Integer>] the type and id from the reference
    def split_ref(ref)
      type, id = ref.split(':')
      [type, id.to_i]
    end

    # @return [ActiveRecord::Base] the record this reference names
    def load_ref(ref)
      type, id = split_ref(ref)
      type.safe_constantize&.find_by(id: id)
    end

    # @return [ActiveRecord::Base] the target of the activity
    def target
      @target ||= load_ref(activity.target)
    end

    # @return [ActiveRecord::Base] the subject of the activity
    def subject
      @subject ||= load_ref(activity.foreign_id)
    end

    # @return [User] the actor of the activity
    def actor
      @actor ||= load_ref(activity.actor)
    end

    # @return [String] the translated string
    def translate(*args)
      opts = args.last.is_a?(Hash) ? args.pop.dup : {}
      opts[:scope] ||= %i[notifications]
      I18n.t(*args, opts)
    end
  end
end
