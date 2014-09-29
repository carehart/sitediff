require 'typhoeus'

class SiteDiff
  class SiteDiffReadFailure < Exception; end

  module Util
    # @class UriWrapper is a workaround for open() rejecting URIs with credentials
    # eg user:password@hostname.com
    class UriWrapper
      # This lets us treat errors or content as one object
      class ReadResult < Struct.new(:content, :error)
        def fixup_read(str)
          if str && !str.valid_encoding?
            str = str.encode('utf-8', 'binary', :invalid => :replace,
              :undef => :replace)
          end
          return str
        end

        def initialize(cont, err = nil)
          super(fixup_read(cont), err)
        end
        def self.error(err); new(nil, err); end
      end

      def initialize(uri)
        @uri = uri.respond_to?(:scheme) ? uri : URI.parse(uri)
      end

      def user
        @uri.user
      end

      def password
        @uri.password
      end

      def no_credentials
        uri_no_credentials = @uri.clone
        uri_no_credentials.user = nil
        uri_no_credentials.password = nil
        return uri_no_credentials
      end

      def to_s
        return no_credentials.to_s
      end

      def +(path)
        uri = @uri.dup
        uri.path += '/' + path
        return self.class.new(uri)
      end

      def read_file(&handler)
        File.open(@uri.to_s, 'r:UTF-8') do |f|
          handler.(ReadResult.new(f.read))
        end
      rescue Errno::ENOENT => e
        handler.(ReadResult.error(e.message))
      end

      def queue_request(q, &handler)
        # Don't hang on servers that don't exist
        params = { :connecttimeout => 3 }

        # Allow basic auth
        if @uri.user
          params[:userpwd] = @uri.user + ':' + @uri.password
        end

        req = Typhoeus::Request.new(self.to_s, params)
        req.on_complete do |resp|
          if resp.success?
            handler.(ReadResult.new(resp.body))
          else
            handler.(ReadResult.error(resp.status_message))
          end
        end
        q.queue(req)
      end

      # Queue reading this URL, with a completion handler to run after.
      #
      # The handler should be callable as handler[ReadResult].
      #
      # This method may choose not to queue the request at all, but simply
      # execute right away.
      def queue(q, &handler)
        if @uri.scheme == nil
          read_file(&handler)
        else
          queue_request(q, &handler)
        end
      end
    end
  end
end