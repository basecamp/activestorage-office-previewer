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

## Security

This gem converts documents that your users upload. Document conversion is a high-risk operation. LibreOffice is a large application with a wide feature set.

Version 0.2.0 adds two defense-in-depth layers:

* **An environment allowlist.** The gem starts `soffice` with a minimal environment. Application secrets in the host environment do not reach the `soffice` process.
* **A throwaway user profile.** Each conversion uses a new LibreOffice profile. The profile refuses active content and externally linked resources.

**Isolate the converter.** These two layers reduce risk. They do not replace process isolation. Run LibreOffice with no access to the host filesystem, no access to host process data, and no access to your secrets. Use a container, a dedicated user account, or a namespace.

## License

This gem is released under the terms of the MIT license.

LibreOffice is released under the terms of the [Mozilla Public License, version 2.0](https://www.libreoffice.org/about-us/licenses/).
