FROM ubuntu:18.04

############################## Install miniconda environement, from miniconda3 Dockerfile ##############################
#  $ docker build . -t continuumio/miniconda3:latest -t continuumio/miniconda3:4.5.11
#  $ docker run --rm -it continuumio/miniconda3:latest /bin/bash
#  $ docker push continuumio/miniconda3:latest
#  $ docker push continuumio/miniconda3:4.5.11

ENV LANG=C.UTF-8 LC_ALL=C.UTF-8
ENV PATH /opt/conda/bin:$PATH
ENV TZ Europe/Zurich

########################### Install system libraries, PANDAseq (libltdl7) dependencies and a package required for png plotting  (libcairo2) ###########################
RUN echo $TZ > /etc/timezone &&\
    ln -snf /usr/share/zoneinfo/$TZ /etc/localtime &&\
    apt-get update && \
    apt-get install -y wget bzip2 ca-certificates curl git libltdl7 libcairo2-dev tzdata && \
    dpkg-reconfigure -f noninteractive tzdata && \
    rm /etc/localtime && \
    apt-get clean && \
    apt-get autoremove -y && \    
    rm -rf /var/lib/apt/lists/*

RUN wget --quiet https://repo.anaconda.com/miniconda/Miniconda3-4.6.14-Linux-x86_64.sh -O ~/miniconda.sh && \
    /bin/bash ~/miniconda.sh -b -p /opt/conda && \
    rm ~/miniconda.sh && \
    /opt/conda/bin/conda clean -tipsy && \
    ln -s /opt/conda/etc/profile.d/conda.sh /etc/profile.d/conda.sh && \
    echo ". /opt/conda/etc/profile.d/conda.sh" >> ~/.bashrc && \
    echo "conda activate base" >> ~/.bashrc

ENV TINI_VERSION v0.16.1
ADD https://github.com/krallin/tini/releases/download/${TINI_VERSION}/tini /usr/bin/tini
RUN chmod +x /usr/bin/tini

############################## Create pipeline_user, set useful variables ##############################
RUN useradd -r -u 1080 pipeline_user
ENV main=/home/pipeline_user
WORKDIR $main
ENV pipeline_folder=${main}/microbiome16S_pipeline
ENV assembly_finder_folder=${main}/assembly_finder

########################### Install java (needed for Qiime tax assignemnt), Snakemake and Simulate_PCR dependancies ##############################
RUN conda config --add channels defaults && \
    conda config --add channels bioconda && \
    conda config --add channels conda-forge && \
    conda install snakemake=5.5.4 blast=2.9.0 perl-lwp-simple perl-bioperl java-jdk conda=4.6.14 
    

## Set in path a patched version of simulate PCR, DOI: 10.1186/1471-2105-15-237 for amplicons validation
RUN wget --quiet https://github.com/metagenlab/updated_simulate_PCR/archive/v0.9.9.tar.gz -O simulate_PCR.tar.gz && \
    mkdir /opt/simulate_PCR && \
    tar xzf simulate_PCR.tar.gz -C /opt/simulate_PCR &&  \
    mv /opt/simulate_PCR/updated_simulate_PCR-0.9.9/code/simulate_PCR /opt/simulate_PCR && \
    rm simulate_PCR.tar.gz && \
    rm -R /opt/simulate_PCR/updated_simulate_PCR-0.9.9 && \
    chmod +x /opt/simulate_PCR/simulate_PCR

ENV PATH="/opt/simulate_PCR:${PATH}"
ENV PERL5LIB="/opt/conda/lib/site_perl/5.26.2"
ENV PATH="/opt/simulate_PCR:${PATH}"

############################## Get the pipeline through github #######################
## Call the access token to reach the private github repo
ARG GITHUB_AT

## Clone the pipeline and assembly_finder, developped by @idfarbanecha
#RUN git clone --single-branch --branch $VERSION https://$GITHUB_AT@github.com/metagenlab/microbiome16S_pipeline.git $pipeline_folder && \
COPY ./data $pipeline_folder/data/
COPY ./envs $pipeline_folder/envs/
COPY ./ressources $pipeline_folder/ressources/
COPY ./rules $pipeline_folder/rules/
COPY ./README* ./
COPY ./Snakefile* ./$pipeline_folder/
RUN echo $GITHUB_AT

RUN git clone --single-branch --branch v0.1.1-alpha https://$GITHUB_AT@github.com/metagenlab/assembly_finder.git $assembly_finder_folder


## Get in the validation directory
WORKDIR ${pipeline_folder}/data/validation_datasets

#################### Build environements of the pipeline #####################
## Here, with "--create-envs-only", we only build the environements
RUN snakemake --snakefile ${pipeline_folder}/Snakefile_validation --use-conda --conda-prefix /opt/conda/ --create-envs-only --configfile config_in_silico.yml insilico_validation && \
    snakemake --snakefile ${pipeline_folder}/Snakefile --use-conda --conda-prefix /opt/conda/ --create-envs-only --configfile config.yml all PICRUSt2_output && \
    conda clean -a

#################### Set final access rights, variables and work dir #####################
RUN chown pipeline_user:pipeline_user ${main}
USER pipeline_user
RUN mkdir -p ${main}/data/analysis \
    ${main}/.config/biopython/Bio/Entrez/DTDs \
    ${main}/.config/biopython/Bio/Entrez/XSDs
ENV HOME ${main}
RUN conda init bash
WORKDIR ${main}/data/analysis/
ENTRYPOINT ["/bin/bash"]

