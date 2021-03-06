# Base class for scrapers of MyAnimeList pages.  Provides a bunch of methods for common elements on
# MyAnimeList pages, such as the sidebar or h2-separated content.
class MyAnimeListScraper < Scraper
  BASE_URL = 'https://myanimelist.net/'.freeze
  SOURCE_LINE = /^[\[\(](Written by .*|Source:.*)[\]\)]$/i
  EMPTY_TEXT = /No .* has been added to this .*|this .* doesn't seem to have a/i
  LANGUAGES = {
    'Brazilian' => 'pt_br',
    'English' => 'en',
    'French' => 'fr',
    'German' => 'de',
    'Hebrew' => 'he',
    'Hungarian' => 'hu',
    'Italian' => 'it',
    'Japanese' => 'ja_jp',
    'Korean' => 'ko',
    'Spanish' => 'es'
  }.freeze

  private

  def response
    @response ||= http.get(@url).tap do |res|
      raise Scraper::PageNotFound if res.status == 404
      raise Scraper::TooManyRequests if res.status == 429
    end
  end

  def page
    @page ||= response.body
  end

  # @return [String] the main header of a standard MAL page
  def header
    page.at_css('#contentWrapper h1').content.strip
  end

  # @return [Nokogiri::XML::Node] The two-column container of a standard MAL page
  def content
    page.at_css('#content > table')
  end

  # @return [Nokogiri::XML::Node] The sidebar of a standard MAL page
  def sidebar
    content.at_css('td:first-child .js-scrollfix-bottom') ||
      main.previous_element
  end

  # @return [Hash<String,Nokogiri::XML::NodeSet] the sections in the MAL sidebar
  def sidebar_sections
    @sidebar_sections ||= parse_sections(sidebar.at_css('h2, .spaceit_pad').parent.children)
  end

  # @return [Nokogiri::XML::Node] The main container of a standard MAL page
  def main
    content.at_css('td:last-child .js-scrollfix-bottom-rel') ||
      content.at_css('#horiznav_nav').parent
  end

  # @return [Hash<String,Nokogiri::XML::NodeSet] the sections in the MAL sidebar
  def main_sections
    @main_sections ||= parse_sections(main.at_css('h2, .normal_header')&.parent&.children)
  end

  # Parse a NodeSet where MAL has separate sections punctuated by <h2> headers
  # @param nodes [Nokogiri::HTML::NodeSet] the nodes to parse
  # @return [Hash<String,Nokogiri::XML::NodeSet>] the nodes divided into sections
  def parse_sections(nodes)
    return {} if nodes.blank?

    # Keep track of what section we're in
    section = nil
    nodes.each_with_object({}) do |node, out|
      # Set up a fresh NodeSet for the current section if we haven't yet
      out[section] ||= Nokogiri::XML::NodeSet.new(page)
      # These nodes have a content but it are invisible
      node.css('script, style, iframe').each(&:remove)

      # Process the node
      if node.name == 'h2' || node['class'] == 'normal_header'
        section = node.xpath('./text()').map(&:content).join.strip
      else
        out[section] << node
      end
    end
  end

  # Clean a section of text to remove stray junk from MAL.
  # @param text [String] the dirty text from MAL
  # @return [String] the cleaned text
  def clean_text(text)
    lines = text.strip.each_line
    lines = lines.reject { |line| SOURCE_LINE =~ line }
    lines.join.strip.delete("\r")
  end

  # @overload id_for_url(url)
  #   Extracts the Type and ID from a MAL URL
  #   @param url [String] the URL from MyAnimeList
  #   @return [Array<String>] a two-item array containing the Type and ID as strings
  # @overload id_for_url(url, type)
  #   Extract the ID from a MAL URL
  #   @param url [String] the URL from MyAnimeList
  #   @param type [String] the type of URL expected
  #   @return [String] the ID that was extracted
  def id_for_url(url, type = nil)
    if type
      %r{/#{type}/(\d+)/}.match(url)[1]
    else
      %r{myanimelist.net/([^/]+)/(\d+)/}.match(url).captures
    end
  end

  # @overload object_for_link(url)
  #   Loads the Kitsu object for a MAL URL
  #   @param url [String] the URL from MyAnimeList
  #   @return [ApplicationRecord,nil] the record in our database which corresponds to this
  # @overload object_for_link(link)
  #   Loads the Kitsu object for a MAL link
  #   @param link [Nokogiri::XML::Node] the link node
  #   @return [ApplicationRecord,nil] the record in our database which corresponds to this
  def object_for_link(link)
    if link.is_a?(Nokogiri::XML::Node)
      object_for_link(link['href'])
    elsif link.is_a?(String)
      kind, id = id_for_url(link)
      Mapping.lookup("myanimelist/#{kind}", id)
    end
  end

  def clean_html(html)
    HtmlCleaner.new(html).to_s
  end

  def base_url
    BASE_URL
  end
end
