##############################################################################
# File: TimeSeries_WGCNA_Wildtype.R                                          #
# Created: April 14, 2020                                                    #
# Author: Adam Faranda                                                       #
# Purpose:                                                                   # 
#                                                                            #
#                                                                            #
##############################################################################

# Analysis Parameters for WGCNA
#    Which genes are included
#    Combat or Not Combat
#    Signed or Unsigned Networks ?
#    Correlation Method ?
#    Blockwise or Non Blockwise?
#    


## Choosing Interesting Modules:  
##     Use "Candidate Profile" Approach -- module corelation with pattern
##     Use "Network Concepts" to identify high connectivity hub genes
##     



############################ Setup Environment ###############################
  
library(edgeR)
library(WGCNA)
library(dplyr)
setwd("~/Documents/LEC_Time_Series/")
min_lfc=1                                          # log fold change threshold
min_cpm=0.50                                       # Minimum overall abundance
max_cpm=10000                                         # Maximum overall abundance
output_prefix="lfc1"                               # Prefix for output files

# Rdata file with dgelist object
dgeFile="LIRTS_Raw_Data/LIRTS_master_dgelist.Rdata" 

## Helper Function filters a count matrix by given criteria
filterCPMmat<-function(
  object = dge, samples = wt_samples, func=cpm,
  lfc = 3, min_log_cpm = 0, max_log_cpm = 100, include_genes = biosig$gene_id, 
  lfc_columns = paste('logFC', LETTERS[1:4], sep="."), deg_table = deg
){
  ecpm<-func(object, log = T)        # Generate a gene x sample log CPM matrix
  
  # Filter differential expression table by fold change and abundance
  dt<-deg_table[
    apply(deg_table[,lfc_columns], 
          1, function(x, l=lfc) any(abs(x) > l)),
    ]
  dt<-dt[dt$logCPM > min_log_cpm & dt$logCPM < max_log_cpm, ]
  dt<-dt[dt$FDR < 0.05, ]
  
  # If a subset of genes is provided, take the intersection
  if (!is.null(include_genes)){
    genes<-intersect(dt$gene_id, include_genes)
  } else{
    genes<-dt$gene_id
  }
  return(ecpm[genes, samples])
}


######################### Load and Prepare Data ##############################
load(dgeFile)
s<-which(master$samples$genotype == "WT")
dge<-master[,s]
design<-model.matrix(~hours_pcs + batch, dge$samples)
colnames(design)<-gsub("hours_pcs", '', colnames(design))
keep<-filterByExpr(dge, design)
dge<-dge[keep,,keep.lib.sizes=F]

# Normalize and Estimate Dispersions
dge<-calcNormFactors(dge)
dge<-estimateDisp(dge, design, robust = T)

# Calcuate Statistical Significance (Gene DE at ANY Timepoint)
fit<-glmQLFit(dge, design)
qlf<-glmQLFTest(fit, coef=2:6)
deg<-as.data.frame(topTags(qlf, n=Inf))

# construct datExpr and datTraits using filteredGenes
datExpr <- read.csv(
  "LIRTS_DEG_Analysis_results/GWT_CombatSeq_Upper50_Disp_TMM-FPKM_Matrix.csv",
  row.names = 1
)
nrow(
  deg %>% filter(
    FDR < 0.05 & (
      abs(logFC.6H)>1 | 
        abs(logFC.24H)>1 | 
        abs(logFC.48H)>1 | 
        abs(logFC.72H)>1 | 
        abs(logFC.120H)>1)
  )
)

deg <- deg%>%filter(
  gene_id %in% row.names(datExpr)
)

deg%>% filter(
  FDR < 0.05 & (
    abs(logFC.6H)>0.5 | 
      abs(logFC.24H)>0.5 | 
      abs(logFC.48H)>0.5 | 
      abs(logFC.72H)>0.5 | 
      abs(logFC.120H)>0.5
  )
) %>% pull("gene_id") -> features

datExpr <- t(datExpr)

# remove columns that hold information we do not need.
allTraits = dge$samples[, -c(2,3,4,7,8,9,10)];
row.names(allTraits)<-allTraits$sample
modbatch<-model.matrix(~ 0 + batch, allTraits)
modhours<-model.matrix(~ 0 + hours_pcs, allTraits)

allTraits<-merge(allTraits, modhours, by='row.names')
row.names(allTraits)<-allTraits$Row.names
allTraits<-allTraits[-1]

allTraits<-merge(allTraits, modbatch,by='row.names')
rownames(allTraits)<-allTraits$sample
allTraits<-allTraits[-1]

allTraits<-allTraits[,-c(1,2,3)]
names(allTraits)<-gsub("batch", "", names(allTraits))
names(allTraits)<-gsub("hours_pcs", "", names(allTraits))


f <- function(y, assign=c(1,2,3,4,5,6)){
  sapply(
    y, function(x){ 
      switch(
        x,
        `0H`=assign[1],
        `6H`=assign[2],
        `24H`=assign[3],
        `48H`=assign[4],
        `72H`=assign[5],
        `120H`=assign[6]
      )
    }
  )
}
candidateProfiles <- dge$samples %>%
  mutate(
    Profile_1=f(
      as.character(hours_pcs),
      assign=c(1,2,3,4,5,6)
    ),
    Profile_2=f(
      as.character(hours_pcs),
      assign=c(1,2,3,3,3,3)
    ),
    Profile_3=f(
      as.character(hours_pcs),
      assign=c(1,2,3,3,2,1)
    ),
    Profile_4=f(
      as.character(hours_pcs),
      assign=c(1,6,5,4,3,2)
    ),
    Profile_5=f(
      as.character(hours_pcs),
      assign=c(3,2,1,2,2,2)
    )
  )
allTraits <- candidateProfiles %>%
  tibble::remove_rownames()%>%
  tibble::column_to_rownames("sample") %>%
  select(matches("Profile"))%>%
  as.data.frame()
########################## Choose best power level ###########################

powers = c(c(1:10), seq(from = 12, to=30, by=2))
# Call the network topology analysis function
sft = pickSoftThreshold(datExpr, powerVector = powers, verbose = 5)


# Scale-free topology fit index as a function of the soft-thresholding power

fn<-paste(output_prefix, "LTS_Wildtype_WGCNA_ScaleAnalysis.png", sep="_")
png(fn)
# Plot the results:
#sizeGrWindow(9, 5)
par(mfrow = c(1,2));
cex1 = 0.9;
plot(sft$fitIndices[,1], -sign(sft$fitIndices[,3])*sft$fitIndices[,2],
     xlab="Soft Threshold (power)",
     ylab="Scale Free Topology Model Fit,signed R^2",type="n",
     main = paste("Scale independence"));
text(sft$fitIndices[,1], -sign(sft$fitIndices[,3])*sft$fitIndices[,2],
     labels=powers,cex=cex1,col="red");
# this line corresponds to using an R^2 cut-off of h
abline(h=0.90,col="red")
# Mean connectivity as a function of the soft-thresholding power
plot(sft$fitIndices[,1], sft$fitIndices[,5],
     xlab="Soft Threshold (power)",ylab="Mean Connectivity", type="n",
     main = paste("Mean connectivity"))
text(sft$fitIndices[,1], sft$fitIndices[,5], labels=powers, cex=cex1,col="red")
dev.off()
  
######################## Build Correlation Network ###########################
net = blockwiseModules(
  datExpr, power = 5, networkType = 'signed',
  TOMType = "signed", minModuleSize = 30,
  reassignThreshold = 0, mergeCutHeight = 0.15,
  numericLabels = TRUE, pamRespectsDendro = FALSE,
  saveTOMs = TRUE,
  saveTOMFileBase = "LEC_Time_Series_Wildtype",
  loadTOM = F,
  verbose = 3
)

moduleLabels = net$colors
moduleColors = labels2colors(net$colors)
MEs = net$MEs;
geneTree = net$dendrograms[[1]]

############################### Plot Results #################################
nGenes = ncol(datExpr);
nSamples = nrow(datExpr);
# Recalculate MEs with color labels
MEs0 = moduleEigengenes(datExpr, moduleColors)$eigengenes
MEs = orderMEs(MEs0)
moduleTraitCor = cor(MEs, allTraits, use = "p");
moduleTraitPvalue = corPvalueStudent(moduleTraitCor, nSamples);


textMatrix =  paste(signif(moduleTraitCor, 2), "\n(",
                    signif(moduleTraitPvalue, 1), ")", sep = "");
dim(textMatrix) = dim(moduleTraitCor)

fn<-paste(output_prefix, "LTS_Wildtype_WGCNA_ModuleTraitCorrelation.pdf" )
pdf(fn)
par(mar = c(6, 7.5, 3, 3));
# Display the correlation values within a heatmap plot
labeledHeatmap(Matrix = moduleTraitCor,
               xLabels = names(allTraits),
               yLabels = names(MEs),
               ySymbols = names(MEs),
               colorLabels = FALSE,
               colors = blueWhiteRed(50),
               textMatrix = textMatrix,
               setStdMargins = FALSE,
               cex.text = 0.5,
               zlim = c(-1,1),
               main = paste("Module-trait relationships"))
dev.off()

#################### Generate Line Plots For Each Module #####################
library(data.table)
library(ggplot2)
samp <- dge$samples
row.names(samp) <- samp$label
dt<-data.table(merge(as.data.frame(datExpr), samp, by='row.names'))
for(c in unique(net$colors)){
  n<-labels2colors(c)
  g<-names(net$colors[net$colors == c])
  x<-melt(
    dt[,c(g, 'hours_pcs'),with=F][,lapply(.SD, mean), by=hours_pcs],
    id.vars = 'hours_pcs'
  )
  fn<-paste(
    output_prefix,
    n, "Module_Lineplot.png",
    sep="_"
  )
  ttl<-paste(n, length(g))
  ggplot(x, aes(x=hours_pcs, y=value, color=variable, group=variable)) + 
    geom_line() + theme(legend.position = 'none') + ggtitle(ttl)
  ggsave(fn)
}




