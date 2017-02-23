require 'octokit'
require 'highline'
require 'git-release/version'

module GitRelease
    $cli = HighLine.new
    $token_file = "~/.git-release-token"
    $status = {
        "r"  => "release",
        "p"  => "prerelease",
        "d"  => "draft",
        "release"  => "release",
        "prerelease"  => "prerelease",
        "draft"  => "draft"
    }

    def self.run(args)
        args << 'help' if args.empty?
        command = args.shift

        case command
        when 'help'
            usage
        when 'version'
            puts "git-release version #{GitRelease::VERSION}"
        when 'login'
            login = do_login
            puts 'successfully logged in'
        when 'list'
            repo = get_repo
            print_releases(repo)
        when 'set'
            repo = get_repo
            tag = args.shift
            status = $status[args.shift] || unknown_status
            set_release(repo, tag, status)
        when 'doc'
            repo = get_repo
            task = args.shift
            tag = args.shift
            case task
            when 'clear'
                clear_doc(repo, tag)
            when 'add'
                add_doc(repo, tag, args)
            end
        end
    end

    def self.usage
        puts "usage: git-release <command> [<args>]"
        puts " help                 print this message"
        puts " version              print the current version"
        puts " login                create or verify api token"
        puts " list                 list all releases"
        puts " set <tag> <state>    change the status of a release"
        puts "     tag              tag of the release to change"
        puts "     state            new state. either r[elease], p[rerelease] or d[raft]"
        puts " doc clear <tag>      clear the release notes"
        puts " doc add <tag> <text> add one or more lines to the release notes"
    end

    def self.unknown_status
        puts "unknown status"
        puts "use one of: r[elease], p[rerelease] or d[raft]"
        exit 1
    end

    def self.get_repo
        repo = `git remote get-url origin`.
            sub("\n", "").
            gsub(/.*github.com./, "")
        if $?.exitstatus == 0
            repo
        else
            puts "not a git repository"
            exit 1
        end
    end

    def self.get_api_client
        Octokit::Client.new(:access_token => load_token)
    end

    def self.get_user_client
        user = ask_username
        pass = ask_password
        client = Octokit::Client.new(:login => user, :password => pass)
    end

    def self.do_login
        if File.file?(File.expand_path($token_file))
            begin
                test = get_api_client
                test.repos
            rescue
                client = get_user_client
                token = get_token(client)
                store_token(token)
            end
        else
            client = get_user_client
            token = get_token(client)
            store_token(token)
        end
    end

    def self.load_token
        begin
            File.open(File.expand_path($token_file), &:readline)
        rescue
            puts "please login first"
            exit 1
        end
    end

    def self.store_token(token)
        f = File.new(File.expand_path($token_file), 'w', 0600)
        f.write(token)
        f.close
    end

    def self.ask_username
        user = $cli.ask("GitHub User: ", String)
        if user.empty?
            exit 1
        end
        user
    end

    def self.ask_password
        pass = $cli.ask("GitHub Password: ", String) { |q| q.echo = "*" }
        if pass.empty?
            exit 1
        end
        pass
    end

    def self.ask_otp
        otp = $cli.ask("GitHub 2FA: ", String)
        if otp.empty?
            exit 1
        end
        otp
    end

    def self.ask_note(note)
        note = $cli.ask("OAuth token note: ", String) { |q| q.default = note }
        if note.empty?
            exit 1
        end
        note
    end

    def self.delete_token(client, note)
        otp = ""
        id = ""
        done = false
        while !done do
            begin
                if id.empty?
                    if otp.empty?
                        auths = client.authorizations
                    else
                        auths = client.authorizations(
                            :headers => { "X-GitHub-OTP" => otp})
                    end
                    id = auths.find { |a| a.note.include?(note) }.id
                else
                    if otp.empty?
                        client.delete_authorization(id)
                    else
                        client.delete_authorization(
                            id,
                            :headers => { "X-GitHub-OTP" => otp})
                    end
                    done = true
                end
            rescue Octokit::OneTimePasswordRequired => e
                otp = ask_otp
            end
        end
    end

    def self.choose_delete(client, note)
        $cli.choose do |menu|
            menu.prompt = "Token '#{note}' already exists: "
            menu.choice("regenerate token (will delete old one)") do
                delete_token(client, note)
                note
            end
            menu.choice("generate token with new name") do
                ask_note(note)
            end
        end
    end

    def self.get_token(client)
        token = ""
        note = 'Git Release CLI',
        otp = ""
        while token.empty? do
            begin
                if otp.empty?
                    token = client.create_authorization(
                        :scopes => ['repo'],
                        :note => note)
                else
                    token = client.create_authorization(
                        :scopes => ['repo'],
                        :note => note,
                        :headers => { "X-GitHub-OTP" => otp})
                end
            rescue Octokit::OneTimePasswordRequired => e
                otp = ask_otp
            rescue Octokit::UnprocessableEntity => e
                if e.message.include?("already_exists")
                    note = choose_delete(client, note)
                else
                    puts e
                    exit 1
                end
            rescue => e
                puts e
                exit 1
            end
        end
        token.token
    end

    def self.print_releases(repo)
        client = get_api_client
        releases = client.releases(repo)
        sorted = releases.sort { |x,y| y.tag_name <=> x.tag_name }
        first_testing = first_production = true
        sorted.each do |r|
            if r.draft
                $cli.say("<%= color('#{r.tag_name} (draft)', :red) %>")
            elsif r.prerelease
                $cli.say("<%= color('#{r.tag_name} (prerelease)', :yellow) %>")
                if first_testing
                    $cli.say("<%= color('current testing', :blue) %>")
                    first_testing = false
                end
            else
                $cli.say("<%= color('#{r.tag_name} (release)', :green) %>")
                if first_testing and first_production
                    $cli.say("<%= color('current testing and production', :blue) %>")
                    first_testing = first_production = false
                elsif first_production
                    $cli.say("<%= color('current production', :blue) %>")
                    first_production = false
                end
            end

            $cli.say("<%= color('released:', :blue) %> #{r.published_at}")
            $cli.say("<%= color('notes:', :blue) %>")
            if !r.body.nil?
                r.body.each_line { |l| $cli.say("  #{l}") }
            end
            puts
        end
        if first_production and first_testing
            $cli.say("<%= color('no release for testing and production!', :red) %>")
        elsif first_production
            $cli.say("<%= color('no release for production!', :red) %>")
        end
    end

    def self.get_tag(releases, tag)
        release = releases.find { |r| r.tag_name == tag }
        if release.empty?
            puts "unknown tag #{tag}"
            exit 1
        end
        release
    end

    def self.set_release(repo, tag, status)
        client = get_api_client
        releases = client.releases(repo)
        release = get_tag(releases, tag)
        case status
        when "release"
            prerelease = false
            draft = false
        when "prerelease"
            prerelease = true
            draft = false
        when "draft"
            prerelease = true
            draft = true
        end

        client.update_release(
            release.url,
            :prerelease => prerelease,
            :draft => draft)
    end

    def self.clear_doc(repo, tag)
        client = get_api_client
        releases = client.releases(repo)
        release = get_tag(releases, tag)
        client.update_release(release.url, :body => "")
    end

    def self.add_doc(repo, tag, text)
        client = get_api_client
        releases = client.releases(repo)
        release = get_tag(releases, tag)

        if text.kind_of?(Array)
            text = text.join("\n")
        end
        if release.body.empty?
            body = text
        else
            body = "#{release.body}\n#{text}"
        end
        client.update_release(release.url, :body => body)
    end
end
