# frozen_string_literal: true

require 'jekyll'
require 'mini_magick'
require 'pathname'
require 'toml'

module ImageGallery
  class GalleryGenerator < Jekyll::Generator
    safe true

    IGNORED_FILES = ['.ds_store', 'thumbs.db'].freeze

    GalleryImageModel = Struct.new(:path, :thumbnail_path, :creation_datetime, :original_path) do
      def to_liquid
        to_h.transform_keys(&:to_s)
      end
    end

    GalleryModel = Struct.new(:id, :name, :images, :highlight_image, :datetime) do
      def to_liquid
        to_h.map do |k, v|
          if k == :datetime
            [k.to_s, { 'year' => v.year, 'month' => v.month, 'day' => v.day }]
          elsif v.class.method_defined?(:to_liquid)
            [k.to_s, v.to_liquid]
          else
            [k.to_s, v]
          end
        end.to_h
      end
    end

    def generate(site)
      galleries_dir = File.join(site.source, '_galleries')
      unless File.directory?(galleries_dir)
        ImageGallery._log(:warn, "No directory found at #{galleries_dir}, skipping gallery generation")
        return
      end

      all_galleries = Dir.chdir(galleries_dir) do
        Dir.glob('**/*/')
      end

      galleries = []
      all_galleries.each do |gallery_path|
        gallery_path_abs = File.join(site.source, '_galleries', gallery_path)

        source_images = Dir.children(gallery_path_abs)
                           .select { |file_name| File.file?(File.join(gallery_path_abs, file_name)) }
                           .reject { |file_name| File.basename(file_name, '.*') == '_metadata' }
                           .reject { |file_name| IGNORED_FILES.include?(file_name.downcase) }

        next if source_images.empty?

        gallery_path_rel = File.join('_galleries', gallery_path)

        gallery_images_and_times = source_images.map do |src_image_file_name|
          src_image_file_path = File.join(gallery_path_rel, src_image_file_name)

          # TODO: this assumes the image at a path doesn't change
          exif = exif_cache.getset(src_image_file_path) do
            ImageGallery._log_once(:info, 'Loading EXIF data. This may take some time on the first run')
            MiniMagick::Image.open(src_image_file_path).exif
          end
          image_time = DateTime.strptime(exif['DateTimeOriginal'], '%Y:%m:%d %H:%M:%S') if exif['DateTimeOriginal']

          {
            path: src_image_file_path,
            creation_datetime: image_time,
          }
        end

        gallery = construct_gallery(gallery_path_abs, gallery_images_and_times)
        gallery.images = copy_images(site, gallery, gallery_path_rel, gallery_images_and_times).sort_by do |gi|
          if gi.creation_datetime.nil?
            1.0 / 0.0
          else
            gi.creation_datetime
          end
        end.reverse

        gallery.highlight_image = gallery.images.detect do |gi|
          basename = File.basename(gi.original_path, '.*')
          basename.start_with?('hl_') || basename.end_with?('_hl')
        end || gallery.images[0]

        galleries << gallery
        site.pages << GalleryPage.new(site, gallery)
      end

      galleries = galleries.sort_by(&:datetime)
      galleries.reverse!

      galleries.group_by { |gallery| gallery.datetime.year }.each do |year, galleries|
        site.pages << GalleryIndexPage.new(site, year, galleries)
      end

      site.data['galleries'] = galleries

      gallery_years = galleries.group_by { |gallery| gallery.datetime.year }.keys.sort
      site.data['gallery_years'] = gallery_years

      if ImageGallery._config_with_defaults(site)['generate_root_index']
        last_gallery_year = gallery_years.max
        site.pages << GalleryIndexPage.new(
          site,
          last_gallery_year,
          galleries.select { |g| g.datetime.year == last_gallery_year },
          override_dir: File.join(*ImageGallery.gallery_path_array(site))
        )
      end
    end

    def construct_gallery(gallery_path_abs, gallery_images)
      gallery = {}

      _ancestors, gallery_id = Pathname.new(gallery_path_abs).split
      gallery_id = gallery_id.to_s

      gallery_regex = /^(\d{4})[-_]?(\d{2})[-_]?(\d{2})[-_]?(.*)$/
      gallery_dir_match = gallery_id.match(gallery_regex)
      if gallery_dir_match
        gallery['id'] = gallery_dir_match[4]
        gallery['name'] = gallery_dir_match[4].split(/[_-]+/).map(&:capitalize).join(' ')
        gallery['datetime'] = DateTime.new(gallery_dir_match[1].to_i, gallery_dir_match[2].to_i, gallery_dir_match[3].to_i)
      else
        ImageGallery._log(:debug, "Gallery name #{gallery_id} doesn't match the expected regex #{gallery_regex}")
        gallery['id'] = gallery_id
        gallery['name'] = gallery_id.split(/[_-]+/).map(&:capitalize).join(' ')
      end

      earliest_image = gallery_images.reject { |gi| gi[:creation_datetime].nil? }.min { |gi| gi[:creation_datetime] }
      gallery['datetime'] = earliest_image[:creation_datetime] if earliest_image

      file_metadata = load_metadata_from_dir(gallery_path_abs)
      gallery = gallery.merge(transform_metadata(file_metadata)) if file_metadata

      if gallery['datetime'].nil?
        raise "Gallery at #{gallery_path_abs} has no datetime specified - it needs to be in EXIF data, the gallery prefix or the _metadata.json file"
      end

      GalleryModel.new(*gallery.transform_keys(&:to_sym).values_at(*GalleryModel.members))
    end

    def load_metadata_from_dir(path)
      ext_to_parsers = [
        ['toml', ->(f) { TOML.load_file(f) }],
        ['json', ->(f) { JSON.parse(File.new(f)) }],
      ]

      path_to_parsers = ext_to_parsers.map do |(ext, fn)|
        full_path = File.join(path, "_metadata.#{ext}")
        [full_path, fn]
      end
      first_existing_file = path_to_parsers.find do |(full_path, _fn)|
        File.file?(full_path)
      end

      if first_existing_file
        full_path, fn = first_existing_file
        fn.call(full_path)
      end
    end

    def transform_metadata(raw_data)
      raw_data.map do |k, v|
        if k == 'datetime'
          [k, DateTime.parse(v)]
        else
          [k, v]
        end
      end.to_h
    end

    def copy_images(site, gallery, gallery_path_rel, gallery_images_and_times)
      image_directory = File.join(*ImageGallery.gallery_path_array(site, gallery.datetime.year, gallery.datetime.month))

      gallery_images_and_times.map do |img_and_time|
        src_image_file_path = img_and_time[:path]
        src_image_file_name = File.basename(src_image_file_path)
        sha = Digest::SHA256.hexdigest(src_image_file_path)
        image_file_name = "#{sha}#{File.extname(src_image_file_path)}"
        thumb_file_name = "#{sha}_t#{File.extname(src_image_file_path)}"

        config = ImageGallery._config_with_defaults(site)

        image_file = CompressedStaticGalleryFile.new(site, site.source, gallery_path_rel, src_image_file_name, image_directory, image_file_name) do |i|
          if config['image_size']
            i.resize("#{config['image_size']['x']}x#{config['image_size']['y']}>")
            ImageGallery._log(:info, "Processing image #{src_image_file_path} to extents #{config['image_size']}")
          else
            ImageGallery._log(:info, "Processing image #{src_image_file_path}")
          end
        end
        thumb_file = CompressedStaticGalleryFile.new(site, site.source, gallery_path_rel, src_image_file_name, image_directory, thumb_file_name) do |i|
          i.gravity('Center')
          i.resize("#{config['thumbnail_size']['x']}x#{config['thumbnail_size']['y']}^")
          i.extent("#{config['thumbnail_size']['x']}x#{config['thumbnail_size']['y']}")
          ImageGallery._log(:info, "Processing image #{src_image_file_path} to #{config['thumbnail_size']}")
        end

        site.static_files.push(image_file).push(thumb_file)

        GalleryImageModel.new(
          File.join('/', image_file.relative_destination),
          File.join('/', thumb_file.relative_destination),
          img_and_time[:creation_datetime],
          src_image_file_path
        )
      end
    end

    def exif_cache
      @@exif_cache ||= Jekyll::Cache.new('jekyll-image-gallery::exif')
    end
  end

  class GalleryPage < Jekyll::Page
    def initialize(site, gallery)
      @site = site
      @base = site.source

      year = gallery.datetime.year
      month = gallery.datetime.month
      @dir = File.join(*ImageGallery.gallery_path_array(site, year, month))

      @basename = gallery.id
      @ext = '.html'
      @name = "#{@basename}#{@ext}"

      config = ImageGallery._config_with_defaults(site)
      @data = {
        'layout' => 'gallery_page',
        'gallery' => gallery,
        'year' => year,
        'title' => [config['title_prefix'], year, gallery.name].join(" #{config['title_seperator']} "),
      }

      data.default_proc = proc do |_, key|
        site.frontmatter_defaults.find(relative_path, :galleries, key)
      end
    end
  end

  class GalleryIndexPage < Jekyll::Page
    def initialize(site, year, galleries, override_dir: nil)
      @site = site
      @base = site.source
      @dir = override_dir || File.join(*ImageGallery.gallery_path_array(site, year))

      @basename = 'index'
      @ext = '.html'
      @name = "#{@basename}#{@ext}"

      config = ImageGallery._config_with_defaults(site)
      @data = {
        'layout' => 'gallery_index',
        'year' => year,
        'galleries' => galleries,
        'title' => [config['title_prefix'], year].join(" #{config['title_seperator']} "),
      }

      data.default_proc = proc do |_, key|
        site.frontmatter_defaults.find(relative_path, :gallery_indexes, key)
      end
    end
  end

  class CompressedStaticGalleryFile < Jekyll::StaticFile
    BROWSER_SUPPORTED_EXTENSIONS = ['.png', '.jpeg', '.jpg'].freeze
    FALLBACK_FORMAT = 'png'.freeze

    def initialize(site, base, source_path, source_name, dest_path, dest_name, &resize_fn)
      super(site, base, source_path, source_name)
      @dest_path = dest_path
      @dest_name = dest_name
      @resize_fn = resize_fn

      # Apples HEIC format isn't supported by browsers. Using filename isn't an ideal heuristic, but it is probably good
      # enough
      @convert_format = false
      unless BROWSER_SUPPORTED_EXTENSIONS.include?(File.extname(@dest_name).downcase)
        @convert_format = true
        @dest_name = "#{File.basename(@dest_name, '.*')}.#{FALLBACK_FORMAT}"
      end
    end

    def destination(dest)
      File.join(dest, @dest_path, @dest_name)
    end

    def relative_destination
      File.join(@dest_path, @dest_name)
    end

    def write(dest)
      dest_path = destination(dest)

      return false if File.exist?(dest_path) && (File.stat(path).mtime.to_i == File.stat(dest_path).mtime.to_i)

      FileUtils.mkdir_p(File.dirname(dest_path))
      FileUtils.rm(dest_path) if File.exist?(dest_path)

      image = MiniMagick::Image.open(path)
      image.combine_options do |i|
        i.auto_orient
        i.strip
        @resize_fn.call(i)
      end
      image.format FALLBACK_FORMAT if @convert_format
      image.write(dest_path)

      File.utime(File.atime(dest_path), mtime, dest_path)

      true
    end
  end

  def self._config_with_defaults(site)
    defaults = {
      'path' => 'gallery',
      'generate_root_index' => false,
      'thumbnail_size' => {
        'x' => 512,
        'y' => 512,
      },
      "title_prefix" => 'Photos',
      "title_seperator" => '|',
    }

    config = site.config
    unless config
      ImageGallery._log_once(:warn, 'No configuration (site.config) found for jekyll-image-gallery, defaults will be used')
      return defaults
    end

    gallery_config = config['gallery']
    unless gallery_config
      ImageGallery._log_once(:warn, 'No configuration found for jekyll-image-gallery, defaults will be used')
      return defaults
    end

    defaults.merge(gallery_config)
  end

  def self._log(level, message)
    Jekyll.logger.public_send(level, "\tjekyll-image-gallery: #{message}")
  end

  def self._log_once(level, message)
    @@seen_log_messages ||= {}
    return if @@seen_log_messages.include?(message)

    @@seen_log_messages[message] = true
    ImageGallery._log(level, message)
  end

  def self.gallery_path_array(site, year = nil, month = nil)
    config = ImageGallery._config_with_defaults(site)

    gallery_path = []
    gallery_path = config['path'].split('/') if config['path']

    gallery_path.push(year.to_s) if year

    if month
      padded_month = format('%02d', month)
      gallery_path.push(padded_month)
    end

    gallery_path
  end

  module Filters
    def gallery_url(gallery)
      site = @context.registers[:site]
      creation_time = gallery['datetime']
      gallery_path = ImageGallery.gallery_path_array(site, creation_time['year'], creation_time['month']).join('/')
      "/#{gallery_path}/#{gallery['id']}.html"
    end

    def gallery_index_url(year)
      site = @context.registers[:site]
      "/#{ImageGallery.gallery_path_array(site, year).join('/')}/"
    end
  end
end

Liquid::Template.register_filter(ImageGallery::Filters)
