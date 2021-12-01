import csv, re, sys, getopt, os, time

# Use-case: scanning a Docker v2 registry that cannot do auto-polling https://docs.lacework.com/integrate-a-docker-v2-registry#container-registry-support
# First, integrate a Container Registry of Docker v2 kind, no need for registry notifications, maybe enable Non-OS Package support
# Then go to Lacework > Resources >  Containers >  Container Image Information and download as CSV
# The first two columns of the CSV are "Repository"	"Image Tag". The 11th column is "Eval Guid"
# We'll call the Lacework API to perform a on-demand scan of all containers from a known Docker v2 repository previously found in the system but where Auto-Polling wasn't available (Nexus, Jfrog, etc).
# For future containers, ideally the inline scanner will be used to scan before they are pushed to the repository

# PRE-REQUISITES: Install and configure the Lacework CLI https://docs.lacework.com/cli/

def main(argv):
    inputfile = ''
    registry = ''
        #registry="myrepo.com"
        #filename="containers_container_image_information.csv"

    try:
        opts, args = getopt.getopt(argv,"hi:r:",["ifile=","registry="])
    except getopt.GetoptError:
        print ('USAGE: -i <inputfile> -r <registry>')
        sys.exit(2)
    for opt, arg in opts:
        if opt == '-h':
            print ('USAGE: -i <inputfile> -r <registry>')
            sys.exit()
        elif opt in ("-i", "--ifile"):
            inputfile = arg
        elif opt in ("-r", "--registry"):
            registry = arg
    print ('Input file is "', inputfile)
    print ('Registry is "', registry)


    with open(inputfile, newline='') as f:
        reader = csv.reader(f)
        for row in reader:
            #print(row[0],row[1])
            m=re.match("%s\/(.*)$"%registry,row[0]) #only scan containers from the docker v2 repo we integrated in Lacework
            eval_guid=row[11]
            if m and eval_guid=="": #avoid already assessed images
                print ("lacework vulnerability container scan %s %s %s" % (registry, m.group(1), row[1]))
                os.system ("lacework vulnerability container scan %s %s %s" % (registry, m.group(1), row[1]))
                #lacework vulnerability container scan <registry> <repository> <tag|digest> [flags]
                time.sleep(1)


if __name__ == "__main__":
   main(sys.argv[1:])
