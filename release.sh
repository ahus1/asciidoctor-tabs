#!/bin/bash

if [ -z $RELEASE_RUBYGEMS_API_KEY ]; then
  echo No API key specified for publishing to rubygems.org. Stopping release.
  exit 1
fi
if [ -z $RELEASE_NPM_TOKEN ]; then
  echo No npm token specified for publishing to npmjs.com. Stopping release.
  exit 1
fi
RELEASE_BRANCH=$GITHUB_REF_NAME
if [ -z $RELEASE_USER ]; then
  export RELEASE_USER=$GITHUB_ACTOR
fi
RELEASE_GIT_NAME=$(curl -s https://api.github.com/users/$RELEASE_USER | jq -r .name)
RELEASE_GIT_EMAIL=$RELEASE_USER@users.noreply.github.com
GEMSPEC=$(ls -1 *.gemspec | head -1)
RELEASE_NAME=$(ruby -e "print (Gem::Specification.load '$GEMSPEC').name")
# RELEASE_VERSION must be an exact version number or else it defaults to the next patch release
if [ -z $RELEASE_VERSION ]; then
  export RELEASE_VERSION=$(ruby -e "print (Gem::Specification.load '$GEMSPEC').version.then { _1.prerelease? ? _1.release.to_s : (_1.segments.tap {|s| s[-1] += 1 }.join ?.) }")
fi
export GEM_RELEASE_VERSION=${RELEASE_VERSION/-/.}

# configure git to push changes
git config --local user.name "$RELEASE_GIT_NAME"
git config --local user.email "$RELEASE_GIT_EMAIL"

# configure gem command for publishing
mkdir -p $HOME/.gem
echo -e "---\n:rubygems_api_key: $RELEASE_RUBYGEMS_API_KEY" > $HOME/.gem/credentials
chmod 600 $HOME/.gem/credentials

# configure npm client for publishing
if [ "$RELEASE_VERSION" != "${RELEASE_VERSION/-/}" ]; then
  RELEASE_NPM_TAG=testing
else
  RELEASE_NPM_TAG=latest
fi
if case $RELEASE_VERSION in 1.0.0-*) ;; *) false;; esac; then
  RELEASE_NPM_TAG=latest
fi
echo -e "//registry.npmjs.org/:_authToken=$RELEASE_NPM_TOKEN" > $HOME/.npmrc

# release!
(
  set -e
  ruby tasks/version.rb
  (
    cd js
    npm i --quiet
    npm run transpile
    npm version --no-git-tag-version $RELEASE_VERSION
    echo '/node_modules/' > .gitignore
    git add dist data
  )
  git commit -a -m "release $RELEASE_VERSION [no ci]"
  git tag -m "version $RELEASE_VERSION" v$RELEASE_VERSION
  gem build $GEMSPEC
  git push origin $(git describe --tags --exact-match)
  gem push $RELEASE_NAME-$GEM_RELEASE_VERSION.gem
  (
    cd js
    npm publish --tag $RELEASE_NPM_TAG
  )
  git push origin $RELEASE_BRANCH
)

exit_code=$?

# nuke npm settings
rm -f $HOME/.npmrc

# nuke gem credentials
rm -rf $HOME/.gem

git status -s -b

exit $exit_code
