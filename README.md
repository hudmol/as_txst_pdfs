# Texas State PDF Finding Aids

An ArchivesSpace plugin that customizes PDF downloads in the public user
interface, accessed via the `Print` button on collection pages.

The design was based on PDF finding aids developed for TXST's previous
system. There are examples [here](examples).

----
Developed by Hudson Molonglo for Texas State University.

&copy; 2022 Hudson Molonglo Pty Ltd.

----


## Compatibility

This plugin was developed against ArchivesSpace v3.0.1. Although it has not
been tested against other versions, it will probably work as expected on all
2.x and 3.x versions.


## Installation

This plugin has no special installation requirements. It has no database
migrations and no external gems.

1.  Download the latest [release](../../releases).
2.  Unpack it into `/path/to/your/archivesspace/plugins/`
3.  Add the plugin to your `config.rb` like this: `AppConfig[:plugins] << 'as_txst_pdfs'`
4.  Restart ArchivesSpace

To confirm installation has been successful, navigate to a collection page in
the public user interface and click on the `Print` button at top right. The
generated PDF should look like the [examples](examples) provided.


## Configuration

There is no further configuration required.

Note that there are three fields in a collection's repository record that are
used when generating the PDF:

  - Repository Name
  - Parent Institution Name
  - Branding Image URL (ref to a banner image for the title page)

Editing repository records does not result in a reindex of the reocrds in the
repository. So if you change any of these values you will likely need to kick
off a manual reindex of the affected repository to see the changes reflected in
the PDFs.


## Customization

This plugin overrides some of the ERB templates in `public/app/views/pdf`.
It also overrides methods in two `public/app/models` classes.

You can further customize this plugin's behavior by inspecting the files in
[public](public) and modifying them.

When upgrading ArchivesSpace, it is good practice to check the overriden files
in ArchivesSpace core to see if there are changes relevant to this plugin and
port them if necessary.

... Enjoy!!
