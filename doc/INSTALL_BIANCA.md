# Installation on `bianca`

This small tutorial will explain to you how to install and run Sarek on a small sample test data on the Swedish UPPMAX cluster `bianca` made for sensitive data.

For more information about `bianca`, follow the [`bianca` user guide](http://uppmax.uu.se/support/user-guides/bianca-user-guide/).
For more information about using Singularity with UPPMAX, follow the [Singularity UPPMAX guide](https://www.uppmax.uu.se/support-sv/user-guides/singularity-user-guide/).

## Install Nextflow

```bash
# Connect to rackham
> ssh -AX [USER]@rackham.uppmax.uu.se
# Or just open a terminal

# create directories
> mkdir install
> mkdir install/bin
> cd install/bin

# Install Nextflow
> curl -s https://get.nextflow.io | bash
> cd ..

# Archive Nextflow
> tar czvf nextflow_v[xx.yy.zz].tgz .nextflow bin/nextflow

# Send the tar to bianca (here using sftp)
# For FileZilla follow the bianca user guide
> sftp [USER]-[PROJECT]@bianca-sftp.uppmax.uu.se:[USER]-[PROJECT]
> put nextflow_v[xx.yy.zz].tgz

# Connect to bianca
> ssh -A [USER]-[PROJECT]@bianca.uppmax.uu.se

# Go to your project
> cd /castor/project/proj_nobackup

# Make and go into a Nextflow directoy
> mkdir tools
> mkdir tools/nextflow
> cd tools/nextflow

# Copy the tar from wharf to the project
> cp /castor/project/proj_nobackup/wharf/[USER]/[USER]-[PROJECT]/nextflow_v[xx.yy.zz].tgz /castor/project/proj_nobackup/tools/nextflow

# extract Nextflow
> tar xzvf nextflow_v[xx.yy.zz].tgz

# Move files
> mv .nextflow nextflow_v[xx.yy.zz]
> mv bin nextflow_v[xx.yy.zz]/bin

# Clean directory
> rm nextflow_v[xx.yy.zz].tgz

# And everytime you're launching Nextflow, don't forget to export the following ENV variables
> export NXF_HOME=/castor/project/proj/nobackup/tools/nextflow/nextflow_v[xx.yy.zz]
> export PATH=${NXF_HOME}/bin:${PATH}
> export NXF_TEMP=$SNIC_TMP
> export NXF_LAUNCHER=$SNIC_TMP
```

## Install Sarek

Sarek use Singularity containers to package all the different tools.

As `bianca` is secure, no direct download is available, so Sarek and the Singularity containers will have to be installed and updated manually.

You can either download Sarek and the containers on your computer (you will need Nextflow and Singularity for that) or on `rackham`, make an archive, and send it to `bianca` using `FileZilla` or `sftp` given your preferences.

All Reference files are already stored in `bianca`.

```bash
# Connect to rackham
> ssh -AX [USER]@rackham.uppmax.uu.se
# Or just open a terminal

# Clone the repository
> git clone https://github.com/SciLifeLab/Sarek.git

# If you want to include the test data, you should use --recursive
> git clone --recursive https://github.com/SciLifeLab/Sarek.git

# Go to the newly created directory
> cd Sarek

# It is also possible to checkout a specific version using
> git checkout <branch, tag or commit>

# Use our script to make an archive to send to bianca
> ./scripts/makeSnapshot.sh

# Or you can also include the test data in this archive using git-archive-all
# Install pip
> curl https://bootstrap.pypa.io/get-pip.py -o get-pip.py
> python get-pip.py

# If it fails due to permission, you could consider using
> python get-pip.py --user

# Install git-archive-all using pip
> pip install git-archive-all
# If you used --user before, you might want to do that here too
> pip install git-archive-all --user
> ./scripts/makeSnapshot.sh --include-test-data

# You will get this message in your terminal
Wrote Sarek-[snapID].tar.gz

# Send the tar to bianca (here using sftp)
# For FileZilla follow the bianca user guide
> sftp [USER]-[PROJECT]@bianca-sftp.uppmax.uu.se:[USER]-[PROJECT]
> put Sarek-[snapID].tar.gz

# To get the containers
# This script will need Singularity and Nextflow installed
> ./scripts/do_all.sh --pull --tag <VERSION>

# Send the containers to bianca using the same method
# They will be in the containers/ directory as .img files

# The archive will be in the wharf folder in your user home on your bianca project

# Connect to bianca
> ssh -A [USER]-[PROJECT]@bianca.uppmax.uu.se

# Go to your project
> cd /castor/project/proj_nobackup

# Make and go into a Sarek directoy (where you will store all Sarek versions)
> mkdir Sarek
> cd Sarek

# Copy the tar from wharf to the project
> cp /castor/project/proj_nobackup/wharf/[USER]/[USER]-[PROJECT]/Sarek-[snapID].tgz /castor/project/proj_nobackup/Sarek

# extract Sarek
> tar xvzf Sarek-[snapID].tgz

# Make a symbolic link to the extracted repository
> ln -s Sarek-[snapID] default
```

The principle is to have every member of your project to be able to use the same Sarek version at the same time. So every member of the project who wants to use Sarek will need to do:

```bash
# Connect to bianca
> ssh -A [USER]-[PROJECT]@bianca.uppmax.uu.se

# Go to your user directory
> cd /home/[USER]

# Make a symbolic link to the default Sarek
> ln -s /castor/project/proj_nobackup/Sarek/default Sarek
```

And then Sarek can be used with:

```bash
> nextflow run ~/Sarek/main.nf -profile slurm --project [PROJECT] ...
```

## Update Sarek

Repeat the same steps as for installing Sarek, and once the tar has been extracted, you can replace the link.

```bash
# Connect to bianca (Connect to rackham first if needed)
> ssh -A [USER]-[PROJECT]@bianca.uppmax.uu.se

# Go to the Sarek directory in your project
> cd /castor/project/proj_nobackup/Sarek

# Remove link
> rm default

# Link to new Sarek version
> ln -s Sarek-[NEWsnapID] default
```

You can for example keep a `default` version that you are sure is working, an make a link for a `testing` or `development`

--------------------------------------------------------------------------------

[![](images/SciLifeLab_logo.png "SciLifeLab")][scilifelab-link]
[![](images/NGI_logo.png "NGI")][ngi-link]
[![](images/NBIS_logo.png "NBIS")][nbis-link]

[nbis-link]: https://www.nbis.se/
[ngi-link]: https://ngisweden.scilifelab.se/
[scilifelab-link]: https://www.scilifelab.se/
