#!/bin/bash

git submodule update --init --recursive

echo "Installing dependencies for account-abstraction-v0.9..."
(cd lib/account-abstraction-v0.9 && yarn install)

echo "Installing dependencies for account-abstraction-v0.8..."
(cd lib/account-abstraction-v0.8 && yarn install)

echo "Installing dependencies for account-abstraction-v0.7..."
(cd lib/account-abstraction-v0.7 && yarn install)

echo "All submodule dependencies have been installed." 