package lwazure

import log "github.com/sirupsen/logrus"

func Run(debug bool) {
	if debug {
		log.SetLevel(log.DebugLevel)
	}

}
