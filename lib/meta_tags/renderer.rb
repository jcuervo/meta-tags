module MetaTags
  # This class is used by MetaTags gems to render HTML meta tags into page.
  class Renderer
    attr_reader :meta_tags, :normalized_meta_tags

    # Initialized a new instance of Renderer.
    #
    # @param [MetaTagsCollection] meta_tags meta tags object to render.
    #
    def initialize(meta_tags)
      @meta_tags = meta_tags
      @normalized_meta_tags = {}
    end

    # Renders meta tags on the page.
    #
    # @param [ActionView::Base] view Rails view object.
    def render(view)
      tags = []

      render_charset(tags)
      render_title(tags)
      render_with_normalization(tags, :description)
      render_with_normalization(tags, :keywords)
      render_refresh(tags)
      render_noindex(tags)
      render_alternate(tags)
      render_links(tags)

      render_hash(tags, :og, :name_key => :property)
      render_hashes(tags)
      render_custom(tags)

      tags.compact.map { |tag| tag.render(view) }.join("\n").html_safe
    end

    protected


    # Renders charset tag.
    #
    # @param [Array<Tag>] tags a buffer object to store tag in.
    #
    def render_charset(tags)
      if charset = meta_tags.extract(:charset)
        tags << Tag.new(:meta, :charset => charset) if charset.present?
      end
    end

    # Renders title tag.
    #
    # @param [Array<Tag>] tags a buffer object to store tag in.
    #
    def render_title(tags)
      title = meta_tags.extract_full_title
      normalized_meta_tags[:title] = title
      tags << ContentTag.new(:title, :content => title, :itemprop => "name") if title.present?
    end

    # Renders meta tag with normalization (should have a corresponding normalize_
    # method in TextNormalizer).
    #
    # @param [Array<Tag>] tags a buffer object to store tag in.
    # @see TextNormalizer
    #
    def render_with_normalization(tags, name)
      value = TextNormalizer.send("normalize_#{name}", meta_tags.extract(name))
      normalized_meta_tags[name] = value
      tags << Tag.new(:meta, :name => name, :content => value) if value.present?
    end

    # Renders noindex and nofollow meta tags.
    #
    # @param [Array<Tag>] tags a buffer object to store tag in.
    #
    def render_noindex(tags)
      meta_tags.extract_noindex.each do |name, content|
        tags << Tag.new(:meta, :name => name, :content => content) if content.present?
      end
    end

    # Renders refresh meta tag.
    #
    # @param [Array<Tag>] tags a buffer object to store tag in.
    #
    def render_refresh(tags)
      if refresh = meta_tags.extract(:refresh)
        tags << Tag.new(:meta, 'http-equiv' => 'refresh', :content => refresh.to_s) if refresh.present?
      end
    end

    # Renders alternate link tags.
    #
    # @param [Array<Tag>] tags a buffer object to store tag in.
    #
    def render_alternate(tags)
      if alternate = meta_tags.extract(:alternate)
        alternate.each do |hreflang, href|
          tags << Tag.new(:link, :rel => 'alternate', :href => href, :hreflang => hreflang) if href.present?
        end
      end
    end

    # Renders links.
    #
    # @param [Array<Tag>] tags a buffer object to store tag in.
    #
    def render_links(tags)
      [ :canonical, :prev, :next, :author, :publisher ].each do |tag_name|
        href = meta_tags.extract(tag_name)
        if href.present?
          @normalized_meta_tags[tag_name] = href
          if tag_name.eql?("canonical")
            tags << Tag.new(:link, :rel => tag_name, :href => href, :itemprop => "url")
          else
            tags << Tag.new(:link, :rel => tag_name, :href => href)
          end
        end
      end
    end

    # Renders complex hash objects.
    #
    # @param [Array<Tag>] tags a buffer object to store tag in.
    #
    def render_hashes(tags, options = {})
      meta_tags.meta_tags.each do |property, data|
        if data.is_a?(Hash)
          process_hash(tags, property, data, options)
          meta_tags.extract(property)
        end
      end
    end

    # Renders a complex hash object by key.
    #
    # @param [Array<Tag>] tags a buffer object to store tag in.
    #
    def render_hash(tags, key, options = {})
      data = meta_tags.meta_tags[key]
      if data.is_a?(Hash)
        process_hash(tags, key, data, options)
        meta_tags.extract(key)
      end
    end

    # Renders custom meta tags.
    #
    # @param [Array<Tag>] tags a buffer object to store tag in.
    #
    def render_custom(tags)
      meta_tags.meta_tags.each do |name, data|
        Array(data).each do |val|
          tags << Tag.new(:meta, :name => name, :content => val)
        end
        meta_tags.extract(name)
      end
    end

    # Recursive method to process all the hashes and arrays on meta tags
    #
    # @param [Array<Tag>] tags a buffer object to store tag in.
    # @param [String, Symbol] property a Hash or a String to render as meta tag.
    # @param [Hash, Array, String, Symbol] content text content or a symbol reference to
    # top-level meta tag.
    #
    def process_tree(tags, property, content, options = {})
      method = case content
      when Hash
        :process_hash
      when Array
        :process_array
      else
        :render_tag
      end
      send(method, tags, property, content, options)
    end

    # Recursive method to process a hash with meta tags
    #
    # @param [Array<Tag>] tags a buffer object to store tag in.
    # @param [String, Symbol] property a Hash or a String to render as meta tag.
    # @param [Hash] content nested meta tag attributes.
    #
    def process_hash(tags, property, content, options = {})
      content.each do |key, value|
        key = key.to_s == '_' ? property : "#{property}:#{key}"
        value = normalized_meta_tags[value] if value.is_a?(Symbol)
        process_tree(tags, key, value, options)
      end
    end

    # Recursive method to process a hash with meta tags
    #
    # @param [Array<Tag>] tags a buffer object to store tag in.
    # @param [String, Symbol] property a Hash or a String to render as meta tag.
    # @param [Array] content array of nested meta tag attributes or values.
    #
    def process_array(tags, property, content, options = {})
      content.each { |v| process_tree(tags, property, v, options) }
    end

    # Recursive method to process a hash with meta tags
    #
    # @param [Array<Tag>] tags a buffer object to store tag in.
    # @param [String, Symbol] property a Hash or a String to render as meta tag.
    # @param [String, Symbol] content text content or a symbol reference to
    # top-level meta tag.
    #
    def render_tag(tags, name, value, options = {})
      name_key = options.fetch(:name_key, :name)
      value_key = options.fetch(:value_key, :content)
      tags << Tag.new(:meta, name_key => name.to_s, value_key => value) unless value.blank?
    end
  end
end
