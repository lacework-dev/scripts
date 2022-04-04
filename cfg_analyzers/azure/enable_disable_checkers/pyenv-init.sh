#!/bin/bash
PYTHON_VERSION="3.8.10"
echo "[START] : pyenv setup ..."

if pyenv -v 1>/dev/null 2>&1 && pyenv virtualenv -h 1>/dev/null 2>&1; then
	if ! pyenv versions | grep "$PYTHON_VERSION$" 1>/dev/null 2>&1; then
		pyenv install $PYTHON_VERSION
		echo "pyenv: installed python version $PYTHON_VERSION"
	fi
	if ! pyenv versions | grep "$PYTHON_VERSION/envs/azure-cfg-analyzer$" 1>/dev/null 2>&1; then
		pyenv virtualenv $PYTHON_VERSION python_3.8.10
		echo "created - virtualenv: 'python_3.8.10' python: '$PYTHON_VERSION'"
	fi
	if [ "$PYENV_VERSION" != "python_3.8.10" ] 1>/dev/null 2>&1; then

	  # Pyenv initialisations
	  eval "$(pyenv init -)"
	  eval "$(pyenv virtualenv-init -)"

	  pyenv activate python_3.8.10
	  echo "activated - virtualenv: 'python_3.8.10' python: '$PYTHON_VERSION'"

	else
		echo "virtualenv: 'python_3.8.10' python: '$PYTHON_VERSION' already activated"
	fi
else
	echo "missing pyenv/pyenv-virtualenv, please install and try again"
	exit 1
fi

echo "[END] : pyenv setup"
