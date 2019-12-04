# Active Storage previewer for Microsoft Office files

Use [LibreOffice](https://www.libreoffice.org/) to generate previews for Microsoft Word documents, Microsoft PowerPoint presentations, and Microsoft Excel spreadsheets in [Active Storage](https://guides.rubyonrails.org/active_storage_overview.html).

## Requirements

* Rails 6.0 or newer
* [LibreOffice](https://www.libreoffice.org/) 6.2 or newer

## Usage

Add the `activestorage-office-previewer` gem to your app’s Gemfile and run `bundle install`:

```ruby
gem "activestorage-office-previewer"
```

Generate previews of Microsoft Office files using Active Storage’s [preview feature](https://guides.rubyonrails.org/active_storage_overview.html#previewing-files).

## License

This gem is released under the terms of the MIT license.

LibreOffice is released under the terms of the [Mozilla Public License, version 2.0](https://www.libreoffice.org/about-us/licenses/).
