# docker run --rm --volume="%CD%:/srv/jekyll" -it jekyll/jekyll sh -c "chown -R jekyll /usr/gem/ && jekyll new %site_name%" && cd %site_name%

set -ex

docker run --rm --volume="$(pwd):/srv/jekyll" -it jekyll/jekyll:4.2.2 sh -c "pwd && bundle -v"
# docker run --rm --volume="$(pwd):/srv/jekyll" -it jekyll/jekyll:4.2.2 sh -c "bundle install && bundle exec jekyll serve"
