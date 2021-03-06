require 'puppet/rest/route'
require 'puppet/network/http_pool'
require 'puppet/network/http/compression'

module Puppet::Rest
  module Routes

    extend Puppet::Network::HTTP::Compression.module

    ACCEPT_ENCODING = 'gzip;q=1.0,deflate;q=0.6,identity;q=0.3'

    def self.ca
      @ca ||= Route.new(api: '/puppet-ca/v1/',
                        server_setting: :ca_server,
                        port_setting: :ca_port,
                        srv_service: :ca)
    end

    # Make an HTTP request to fetch the named certificate
    # @param [String] name the name of the certificate to fetch
    # @param [Puppet::SSL::SSLContext] ssl_context the ssl content to use when making the request
    # @raise [Puppet::Rest::ResponseError] if the response status is not OK
    # @return [String] the PEM-encoded certificate or certificate bundle
    def self.get_certificate(name, ssl_context)
      ca.with_base_url(Puppet::Network::Resolver.new) do |url|
        header = { 'Accept' => 'text/plain', 'Accept-Encoding' => ACCEPT_ENCODING }
        url.path += "certificate/#{name}"

        use_ssl = url.is_a? URI::HTTPS

        client = Puppet::Network::HttpPool.connection(url.host, url.port, use_ssl: use_ssl, ssl_context: ssl_context)

        response = client.get(url.request_uri, header)
        unless response.code.to_i == 200
          raise Puppet::Rest::ResponseError.new(response.message, response)
        end

        Puppet.info _("Downloaded certificate for %{name} from %{server}") % { name: name, server: ca.server }

        uncompress_body(response)
      end
    end

    # Make an HTTP request to fetch the named crl
    # @param [String] name the crl to fetch
    # @param [Puppet::SSL::SSLContext] ssl_context the ssl content to use when making the request
    # @raise [Puppet::Rest::ResponseError] if the response status is not OK
    # @return [String] the PEM-encoded crl
    def self.get_crls(name, ssl_context)
      ca.with_base_url(Puppet::Network::Resolver.new) do |url|
        header = { 'Accept' => 'text/plain', 'Accept-Encoding' => ACCEPT_ENCODING }
        url.path += "certificate_revocation_list/#{name}"

        use_ssl = url.is_a? URI::HTTPS

        client = Puppet::Network::HttpPool.connection(url.host, url.port, use_ssl: use_ssl, ssl_context: ssl_context)

        response = client.get(url.request_uri, header)
        unless response.code.to_i == 200
          raise Puppet::Rest::ResponseError.new(response.message, response)
        end

        Puppet.info _("Downloaded certificate revocation list for %{name} from %{server}") % { name: name, server: ca.server }

        uncompress_body(response)
      end
    end

    # Make an HTTP request to send the named CSR
    # @param [String] csr_pem the contents of the CSR to sent to the CA
    # @param [String] name the name of the host whose CSR is being submitted
    # @param [Puppet::SSL::SSLContext] ssl_context the ssl content to use when making the request
    # @rasies [Puppet::Rest::ResponseError] if the response status is not OK
    def self.put_certificate_request(csr_pem, name, ssl_context)
      ca.with_base_url(Puppet::Network::Resolver.new) do |url|
        header = { 'Accept' => 'text/plain',
                   'Accept-Encoding' => ACCEPT_ENCODING,
                   'Content-Type' => 'text/plain' }
        url.path += "certificate_request/#{name}"

        use_ssl = url.is_a? URI::HTTPS

        client = Puppet::Network::HttpPool.connection(url.host, url.port, use_ssl: use_ssl, ssl_context: ssl_context)

        response = client.put(url.request_uri, csr_pem, header)
        if response.code.to_i == 200
          Puppet.debug "Submitted certificate request to server."
        else
          raise Puppet::Rest::ResponseError.new(response.message, response)
        end
      end
    end

    # Make an HTTP request to get the named CSR
    # @param [String] name the name of the host whose CSR is being queried
    # @param [Puppet::SSL::SSLContext] ssl_context the ssl content to use when making the request
    # @rasies [Puppet::Rest::ResponseError] if the response status is not OK
    # @return [String] the PEM encoded certificate request
    def self.get_certificate_request(name, ssl_context)
      ca.with_base_url(Puppet::Network::Resolver.new) do |url|
        header = { 'Accept' => 'text/plain', 'Accept-Encoding' => ACCEPT_ENCODING }
        url.path += "certificate_request/#{name}"

        use_ssl = url.is_a? URI::HTTPS

        client = Puppet::Network::HttpPool.connection(url.host, url.port, use_ssl: use_ssl, ssl_context: ssl_context)

        response = client.get(url.request_uri, header)
        unless response.code.to_i == 200
          raise Puppet::Rest::ResponseError.new(response.message, response)
        end

        Puppet.debug _("Downloaded existing certificate request for %{name} from %{server}") % { name: name, server: ca.server }

        uncompress_body(response)
      end
    end
  end
end
