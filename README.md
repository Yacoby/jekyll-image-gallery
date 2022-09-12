# Jekyll Image Gallery
A image gallery generator for Jekyll. The differentiating feature from other gallery plugins is that it generates galleries
automatically grouped into years.

The feature list is pretty standard:
- Thumbnail generation
- Optional image compression
- Exif data stripping
- Automatic conversion of raw formats (e.g. [HEIC](https://en.wikipedia.org/wiki/High_Efficiency_Image_File_Format)) into browser supported formats

Example can be found at [photos.jacobessex.com](https://photos.jacobessex.com) \[[source](https://github.com/Yacoby/photos.jacobessex.com)\]

### Alternatives

Also consider:
- [cheesy-gallery](https://github.com/DavidS/cheesy-gallery) - Allows more flexibility in structure
- [jekyll-gallery-generator](https://github.com/ggreer/jekyll-gallery-generator) - Similar to this plugin but without the year based grouping

## Installation
See the [Jekyll guide on installing plugins](https://jekyllrb.com/docs/plugins/installation/) and install "jekyll-image-gallery"

Ensure you install the transitive dependency ImageMagick, as this is required by the [mini_magick](https://github.com/minimagick/minimagick) gem. On Mac this is as simple as
```
$ brew install imagemagick
```

## Usage

After installation, create a `_galleries` directory and within the `_galleries` directory, create sub-directories for each gallery. For example your directory structure could look like this:

```
- _galleries/
--- 2022/
----- 2022-05-23-first-gallery/
------- first_image.jpg
------- second_image.png
----- 2022-09-01-second/
------- awesome.jpg
```

This will result in the generated galleries:
```
- _site/
--- index.html (optional root index.html)
--- 2022/
----- index.html
----- 05/
------- first-gallery.html
------- first_image.jpg
------- second_image.png
------- [.. and thumbnails ..]
----- 09/
------- second.html
------- awesome.jpg
------- [.. and thumbnails ..]
```

As you can see from the example, the directory structure you use doesn't matter, each sub directory containing images will be considered its own gallery (even subdirectories nested in an existing gallery) and the structure will be based on the year and the month of each gallery.

The year and month of the gallery is inferred from the first of
- The \_metadata file (see the "Per gallery configuration" section), if it exists and the key is set
- The earliest date contained in image Exif data if the images have Exif data
- The gallery directory name (if suffixed with an date)

### Layouts

This plugin generates pages which use two layouts
- `gallery_index` - an index of galleries
- `gallery_page` - the gallery itself

These layouts are not included in the plugin and so you will need to implement them yourself. An example can be found [here](https://github.com/Yacoby/photos.jacobessex.com/tree/master/_layouts)

### Highlighted image

The gallery index page displays a thumbnail for the image gallery. By default this is the first image but a specific image
can be chosen by prefixing the image name with `hl_` or suffixing it with `_hl`. e.g. `myimage_hl.png`.

### Plugin Configuration

Global gallery configuration uses the standard Jekyll configuration (default of `_config.yaml`)

```yaml
gallery:
  generate_root_index: true # Generate a index gallery at the root of the gallery (default false)
  path: 'some/path' # Slash seperated output path of the gallery, set to an empty string to generate a gallery in the root of the site
                    # (default is 'gallery')
  title_prefix: 'Photos' # The prefix of the title variable (default is 'Photos')
  title_seperator: '|' # The seperator between the title components (prefix, year and gallery title). (default is '|')

  thumbnail_size: # Size of generated thumbnails
    x: 512
    y: 512

  image_size: # The maximum size of images, remove the configuration to not compress images (default is no compression)
    x: 2048
    y: 2048
```

### Per gallery configuration

Gallery configuration can be overridden by adding a `_metadata.toml` or `_metadata.json` file to the gallery directory.

```toml
name = "Gallery Name"
datetime = "2001-02-03T04:05:06+07:00"
```

The datetime field is parsed using the [Datetime::parse method](https://ruby-doc.org/stdlib-2.6.1/libdoc/date/rdoc/DateTime.html)


## Development

After checking out the repo, run `bin/setup` to install dependencies. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and the created tag, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
