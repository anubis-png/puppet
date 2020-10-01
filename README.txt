Documentation (and detailed install instructions) can be found 
online at http://reductivelabs.com/trac/puppet/wiki/DocumentationStart .

Generally, you need the following things installed:

* Ruby >= 1.8.1 (earlier releases might work but probably not)

* The Ruby OpenSSL library.  For some reason, this often isn't included
  in the main ruby distributions.  You can test for it by running
  'ruby -ropenssl -e "puts :yep"'.  If that errors out, you're missing the
  library.

  If your distribution doesn't come with the necessary library (e.g., on Debian
  and Ubuntu you need to install libopenssl-ruby), then you'll probably have to
  compile Ruby yourself, since it's part of the standard library and not
  available separately.  You could probably just compile and install that one
  library, though.
.gitignore
History.txt
MIT-LICENSE
Manifest.txt
README
Rakefile
bin/capture
config/hoe.rb
config/requirements.rb
lib/capture.rb
lib/capture/extensions.rb
lib/capture/nikon.jpg
lib/capture/screen.rb
lib/capture/version.rb
script/destroy
script/generate
script/txt2html
setup.rb
spec/capture_spec.rb
spec/spec.opts
spec/spec_helper.rb
tasks/deployment.rake
tasks/environment.rake
tasks/website.rake
website/images/nikon.jpg
website/index.html
website/index.txt
website/javascripts/rounded_corners_lite.inc.js
website/stylesheets/screen.css
website/template.rhtml
* The Ruby XMLRPC client and server libraries.  For some reason, this often
  isn't included in the main ruby distributions.  You can test for it by
  running 'ruby -rxmlrpc/client -e "puts :yep"'.  If that errors out, you're missing
  the library.

* Facter => 1.1.1
  You can get this from < http://reductivelabs.com/projects/facter >

$Id$
