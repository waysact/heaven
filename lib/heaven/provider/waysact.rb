module Heaven
  # Top-level module for providers.
  module Provider
    # The Waysact provider.
    class Waysact < DefaultProvider

      ALLOWED_ENVIRONMENTS = ["vagrant", "staging"]

      def initialize(guid, payload)
        super
        @name = "waysact"
      end

      def ansible_root
        "#{checkout_directory}"
      end

      def execute

        return execute_and_log(["/usr/bin/true"]) if Rails.env.test?

        fail "Unknown deployment environment #{environment}" unless ALLOWED_ENVIRONMENTS.include? environment

        unless File.exist?(checkout_directory)
          playbook_repository_url = "https://#{ENV['GITHUB_USER']}:#{ENV["GITHUB_TOKEN"]}@github.com/waysact/waysact-ansible.git"
          log "Cloning #{playbook_repository_url} into #{checkout_directory}"
          execute_and_log(["git", "clone", "--branch=ant/heaven", playbook_repository_url, checkout_directory])
        end

        Dir.chdir(checkout_directory) do
          log "Fetching the latest code"
          execute_and_log(%w{git fetch})
          execute_and_log(["git", "reset", "--hard"])

          ansible_hosts_file = "#{ansible_root}/inventories/#{environment}"
          ansible_site_file = "#{ansible_root}/site.yml"
          ansible_extra_vars = [
            "heaven_deploy_sha=#{sha}",
            "ansible_ssh_private_key_file=#{working_directory}/.ssh/id_rsa"
          ].join(" ")

          ansible_vault_password = ENV["ANSIBLE_VAULT_PASSWORD"]
          # ansible-vault doesn't have an argument to read the vault password
          # directly instead an executable which should output the password can
          # be specified with the --vault-password-file argument. The cat
          # command is used to read the password from stdin. Idea from the
          # ansible developers mailing list:
          # https://groups.google.com/d/msg/ansible-devel/1vFc3y6Ogto/ne0xKq5pQXcJ
          deploy_string = ["ansible-playbook", "-i", ansible_hosts_file, ansible_site_file, "--tags", "deploy", "-u", "vagrant",
                           "--verbose", "--extra-vars", ansible_extra_vars, "--extra-vars", "@vaults/#{environment}_secrets.yml",
                           "--vault-password-file=/bin/cat", "-vvvv"]
          log "Executing ansible: #{deploy_string.join(" ")}"
          execute_and_log(deploy_string,  deployment_environment, ansible_vault_password)
        end
      end

      def deployment_environment
        {
          "ANSIBLE_HOST_KEY_CHECKING" => "false",
          "GITHUB_ACCESS_TOKEN" => ENV["GITHUB_TOKEN"]
        }
      end
    end
  end
end
