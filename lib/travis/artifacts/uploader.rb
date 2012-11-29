require 'find'
require 'fog'

module Travis::Artifacts
  class Uploader
    include Travis::Artifacts::Logger

    attr_reader :paths, :target_path

    def initialize(paths, target_path = nil)
      @paths  = paths
      @test   = Test.new
      @target_path = target_path || "artifacts/#{@test.build_number}/#{@test.job_number}"
    end

    def upload
      files.each do |file|
        upload_file(file)
      end
    end

    def files
      files = []

      paths.each do |artifact_path|
        to   = artifact_path.to
        from = artifact_path.from
        root = artifact_path.root

        if artifact_path.directory?
          root = File.join(root, from)
          root << '/' unless root =~ /\/$/
        end

        Find.find(artifact_path.fullpath) do |path|
          next unless File.file? path

          relative = path.sub(/#{root}\/?/, '')

          destination = if to
            artifact_path.directory? ? File.join(to, relative) : to
          else
            relative
          end

          files << Artifact.new(path, destination)
        end
      end

      files
    end


    def upload_file(file)
      retries = 0

      begin
        _upload(file)
      rescue StandardError => e
        if retries < 3
          logger.info "Attempt to upload failed, retrying"
          retries += 1
          retry
        else
          raise
        end
      end
    end

    def _upload(file)
      destination = File.join(target_path, file.destination)

      logger.info "Uploading file #{file.source} to #{destination}"

      bucket.files.create({
        :key => destination,
        :public => true,
        :body => file.read,
        :content_type => file.content_type,
        :metadata => { "Cache-Control" => 'public, max-age=315360000'}
      })
    end

    private

    def job_id
      test.job_id
    end

    def bucket
      @bucket ||= s3.directories.get(Travis::Artifacts.bucket_name)
    end

    def s3
      @s3 ||= begin
        config = { :provider => 'AWS' }.merge Travis::Artifacts.aws_config
        Fog::Storage.new(config)
      end
    end
  end
end
