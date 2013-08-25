module Webmention
  class Client
    # Public: Returns a URI of the url initialized with.
    attr_reader :url

    # Public: Returns an array of links contained within the url.
    attr_reader :links

    # Public: Create a new client
    #
    # url - The url you want us to crawl.
    def initialize(url)
      @url = URI.parse(url)
      @links ||= Set.new

      unless Webmention::Client.valid_http_url? @url
        raise ArgumentError.new "#{@url} is not a valid HTTP or HTTPS URI."
      end
    end

    # Public: Crawl the url this client was initialized with.
    #
    # Returns the number of links found.
    def crawl
      @links ||= Set.new
      if @url.nil?
        raise ArgumentError.new "url is nil."
      end

      Nokogiri::HTML(open(self.url)).css('a').each do |link|
        link = link.attribute('href').to_s
        if Webmention::Client.valid_http_url? link
          @links.add link
        end
      end

      return @links.count
    end

    # Public: Sends mentions to each of the links found in the page.
    #
    # Returns the number of links mentioned.
    def send_mentions
      if self.links.nil? or self.links.empty?
        self.crawl
      end

      cnt = 0
      self.links.each do |link|
        endpoint = Webmention::Client.supports_webmention? link
        if endpoint
          cnt += 1 if Webmention::Client.send_mention endpoint, self.url, link
        end
      end

      return cnt
    end

    # Public: Send a mention to an endoint about a link from a link.
    #
    # endpoint - URL to send mention to.
    # where - Source of mention.
    # who - The link that was mentioned.
    #
    # Returns a boolean.
    def self.send_mention endpoint, where, who
      data = {
        :source => where,
        :target => who,
      }

      uri = URI.parse(endpoint)
      http = Net::HTTP.new(uri.host, uri.port)

      request = Net::HTTP::Post.new(uri.request_uri)
      request.set_form_data(data)
      request['Content-Type'] = "application/x-www-form-urlencoded"
      request['Accept'] = 'application/json'
      response = http.request(request)

      return response.code.to_i == 200
    end

    # Public: Curl a url and check if it supports webmention or pingbacks.
    #
    # url - URL to check
    #
    # Returns false if does not support webmention or pingback, returns string
    # of url to ping if it does.
    def self.supports_webmention? url
      return false if !Webmention::Client.valid_http_url? url

      doc = nil

      begin
        uri = URI.parse(url)
        http = Net::HTTP.new(uri.host, uri.port)
        http.open_timeout = 3 # in seconds
        http.read_timeout = 3 # in seconds

        request = Net::HTTP::Get.new(uri.request_uri)
        request["User-Agent"] = "Ruby WebMention Gem"
        request["Accept"] = "*/*"

        response = http.request(request)

        # First check the HTTP Headers
        if !response["Link"].nil? and response["Link"].match %r{<(https?://[^>]+)>; rel="http://webmention\.org/"}
          matches = response["Link"].match %r{<(https?://[^>]+)>; rel="http://webmention\.org/"}
          return matches[1]
        end

        # Now parse the body
        doc = Nokogiri::HTML(response.body.to_s)

        # Do we support webmention?
        if !doc.css('link[rel="http://webmention.org/"]').empty?
          return doc.css('link[rel="http://webmention.org/"]').attribute("href").value
        end

        # Last chance, do we support Pingback?
        if !doc.css('link[rel="pingback"]').empty?
          return doc.css('link[rel="pingback"]').attribute("href").value
        end

      rescue EOFError
      rescue Errno::ECONNRESET
      end

      return false
    end

    # Public: Use URI to parse a url and check if it is HTTP or HTTPS.
    #
    # url - URL to check
    #
    # Returns a boolean.
    def self.valid_http_url? url
      if url.is_a? String
        url = URI.parse(url)
      end

      return (url.is_a? URI::HTTP or url.is_a? URI::HTTPS)
    end
  end
end
