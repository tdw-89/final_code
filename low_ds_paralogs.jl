using HypothesisTests
using CSV
using DataFrames
using CategoricalArrays
using PlotlyJS

function in_significant_range(gene, sig_ranges, ind)
    in_range = zeros(Bool, length(sig_ranges))
    for (i,sig_range) in enumerate(sig_ranges)
        if siginrange(gene, sig_range, ind)
            sum(getsiginrange(gene, sig_range, ind)) > 0 ? in_range[i] = true : in_range[i] = false
        else
            in_range[i] = false
        end
    end

    return any(in_range)
end

LOW_DS_THRESHOLD = 2

include("./custom_lib/load_gff.jl")
include("./custom_lib/enrichment_utils.jl")
include("./custom_lib/misc_utils.jl")

# Genome data
gff_data = "../../../../data/AX4/genome_ver_2_7/ensembl_52/Dictyostelium_discoideum.dicty_2.7.52.gff3"
chrom_lengths_file = "../../../../data/AX4/genome_ver_2_7/ensembl_52/chromosome_lengths_ensembl.txt"

# Expression data
expr_data_file = "./data/filtered/expr_data_filt_kallisto_ensembl52_single.tsv"

# Peak files
chip_peak_file_dir = "../../../../data/wang_et_al/processed/run_1_ensembl52/"
atac_peak_file_dir = "../../../../data/wang_et_al/processed/run_2_ensembl52/"

# Paralog data
paralog_file = "./data/filtered/paralog_filt.tsv"

# Singleton list
singleton_list_file = "./data/filtered/singleton_filt.tsv"

# Load expression data
expr_data = CSV.read(expr_data_file, DataFrame)

# Rename the expression columns to a letter indicating with life-cycle stage the sample
# was taken from.
rename!(expr_data, ["GeneID", "V", "S", "M", "F"])
expr_data[!,2:end] = log2.(expr_data[!,2:end] .+ 0.5)

# Load peak data
peak_files = [filter(fn -> !contains(fn, r"_S[AB]_"), readdir(chip_peak_file_dir, join=true)); readdir(atac_peak_file_dir, join=true)]
filter!(fn -> endswith(fn, ".narrowPeak"), peak_files)
peak_data = binpeaks(peak_files, chrom_lengths_file)

# Load paralog and singleton data
paralog_data = CSV.read(paralog_file, DataFrame)
singleton_list = CSV.read(singleton_list_file, DataFrame)

# Filter the singleton data to just those that have expression data (paralogs are already filtered)
filter!(row -> row.GeneID in expr_data.GeneID, singleton_list)

# Filter paralogs according to id threshold
select!(paralog_data, ["GeneID", "ParalogID", "dS"])
filter!(row -> row.dS <= 3.0, paralog_data)

# Filter to pairs which have expression data for both
filter!(row -> row.GeneID in expr_data.GeneID && row.ParalogID in expr_data.GeneID, paralog_data) 

# Load reference genome object
ref_genome = loadgenome(gff_data, chrom_lengths_file)

# Add data to reference
addexpression!(ref_genome, expr_data)
addtogenes!(ref_genome, peak_data)

# Get the dS values and quantiles for the filtered pairs
quantile_labels = cut(paralog_data[!, 3], 10)
quantile_vals = levelcode.(quantile_labels)

# Individual expression vs K9me3 enrichment
    # Low dS paralog genes
paralog_genes_low = get(ref_genome, String.(vcat(paralog_data.GeneID[quantile_vals .<= LOW_DS_THRESHOLD], paralog_data.ParalogID[quantile_vals .<= LOW_DS_THRESHOLD])))
paralog_gene_expr_low = [mean(gene.rnas[1].expression) for gene in paralog_genes_low]
k9me3_ranges = [GeneRange(TSS(), TSS(), -500, 100),
                GeneRange(TES(), TES(), -100, 500)]
paralog_gene_has_k9me3_low_1 = [in_significant_range(gene, k9me3_ranges, 3) for gene in paralog_genes_low]
paralog_gene_has_k9me3_low_2 = [in_significant_range(gene, k9me3_ranges, 6) for gene in paralog_genes_low]
paralog_gene_has_k9me3_low_3 = [in_significant_range(gene, k9me3_ranges, 9) for gene in paralog_genes_low]
paralog_gene_has_k9me3_low = paralog_gene_has_k9me3_low_1 .| paralog_gene_has_k9me3_low_2 .| paralog_gene_has_k9me3_3

has_k9_expr_low = paralog_gene_expr_low[paralog_gene_has_k9me3_low]
no_k9_expr_low = paralog_gene_expr_low[.!paralog_gene_has_k9me3_low]
plot([box(y=has_k9_expr_low, name="Has K9me3"), box(y=no_k9_expr_low, name="No K9me3")])
pvalue(MannWhitneyUTest(has_k9_expr_low, no_k9_expr_low))

    # Other paralog genes
paralog_genes_other = get(ref_genome, String.(vcat(paralog_data.GeneID[quantile_vals .> LOW_DS_THRESHOLD], paralog_data.ParalogID[quantile_vals .> LOW_DS_THRESHOLD])))
paralog_gene_expr_other = [mean(gene.rnas[1].expression) for gene in paralog_genes_other]
paralog_gene_has_k9me3_other_1 = [in_significant_range(gene, k9me3_ranges, 3) for gene in paralog_genes_other]
paralog_gene_has_k9me3_other_2 = [in_significant_range(gene, k9me3_ranges, 6) for gene in paralog_genes_other]
paralog_gene_has_k9me3_other_3 = [in_significant_range(gene, k9me3_ranges, 9) for gene in paralog_genes_other]
paralog_gene_has_k9me3_other = paralog_gene_has_k9me3_other_1 .| paralog_gene_has_k9me3_other_2 .| paralog_gene_has_k9me3_other_3

has_k9_expr_other = paralog_gene_expr_other[paralog_gene_has_k9me3_other]
no_k9_expr_other = paralog_gene_expr_other[.!paralog_gene_has_k9me3_other]
plot([box(y=has_k9_expr_other, name="Has K9me3"), box(y=no_k9_expr_other, name="No K9me3")])
pvalue(MannWhitneyUTest(has_k9_expr_other, no_k9_expr_other))

    # overall
pvalue(MannWhitneyUTest(vcat(has_k9_expr_low, has_k9_expr_other), vcat(no_k9_expr_low, no_k9_expr_other)))


    # Singleton genes
singleton_genes = [gene for gene in ref_genome.genes[2] if gene.id in singleton_list.GeneID]
singleton_genes = filter(gene -> has_expr(gene), singleton_genes)
singleton_expr = [mean(gene.rnas[1].expression) for gene in singleton_genes]
singleton_has_k9me3_1 = [in_significant_range(gene, k9me3_ranges, 3) for gene in singleton_genes]
singleton_has_k9me3_2 = [in_significant_range(gene, k9me3_ranges, 6) for gene in singleton_genes]
singleton_has_k9me3_3 = [in_significant_range(gene, k9me3_ranges, 9) for gene in singleton_genes]

singleton_has_k9me3 = singleton_has_k9me3_1 .| singleton_has_k9me3_2 .| singleton_has_k9me3_3

other_has_k9_expr = singleton_expr[singleton_has_k9me3]
other_no_k9_expr = singleton_expr[.!singleton_has_k9me3]


cont_table_sing_vs_low = [length(other_has_k9_expr) length(has_k9_expr_low);
                            length(other_no_k9_expr) length(no_k9_expr_low)]

pvalue(FisherExactTest(cont_table_sing_vs_low[1, 1], cont_table_sing_vs_low[1, 2], cont_table_sing_vs_low[2, 1], cont_table_sing_vs_low[2, 2]))

cont_table_low_vs_other = [length(has_k9_expr_other) length(has_k9_expr_low);
                            length(no_k9_expr_other) length(no_k9_expr_low)]

pvalue(FisherExactTest(cont_table_low_vs_other[1, 1], cont_table_low_vs_other[1, 2], cont_table_low_vs_other[2, 1], cont_table_low_vs_other[2, 2]))

# Table for plotting  (in R):
low_ds_df = DataFrame(
    :GeneID => [gene.id for gene in paralog_genes_low],
    :HasK9me3 => paralog_gene_has_k9me3,
    :HasK27ac => false,
    :HasK4me3 => false,
    :HasATAC => false,
    :Expr => paralog_gene_expr_low
)

# Add H3K4me3, H3K27ac, and ATAC data
sig_regions = CSV.read("data/sig_regions.csv", DataFrame)
sig_regions = Dict([row.Mark => GeneRange(TSS(), TES(), row.Start, row.End) for row in eachrow(sig_regions)])

k27ac_inds = [1,4,7]
k4me3_inds = [2,5,8]
atac_inds = [10,11,12]

Threads.@threads for i in eachindex(paralog_genes_low)

    gene = paralog_genes_low[i]

    if siginrange(gene, sig_regions["K27ac"], 1)
        low_ds_df.HasK27ac[i] = sum([sum(getsiginrange(gene, sig_regions["K27ac"], ind)) for ind in k27ac_inds]) > 0
    
    else
        @warn "K27ac data for gene $i ($(gene.id)) not in range"
        low_ds_df.HasK27ac[i] = sum([sum(getsiginrange(gene, GeneRange(TSS(), TES(), 0, 0), ind)) for ind in k27ac_inds])
    
    end

    if siginrange(gene, sig_regions["K4me3"], 1)
        low_ds_df.HasK4me3[i] = sum([sum(getsiginrange(gene, sig_regions["K4me3"], ind)) for ind in k4me3_inds]) > 0
    
    else
        @warn "H3K4me3 data for $i ($(gene.id)) not in range"
        low_ds_df.HasK4me3[i] = sum([sum(getsiginrange(gene, GeneRange(TSS(), TES(), 0, 0), ind)) for ind in k4me3_inds]) > 0
    
    end

    if siginrange(gene, sig_regions["ATAC"], 1)
        low_ds_df.HasATAC[i] = sum([sum(getsiginrange(gene, sig_regions["ATAC"], ind)) for ind in atac_inds]) > 0
    
    else
        @warn "ATAC data for $i ($(gene.id)) not in range"
        low_ds_df.HasATAC[i] = sum([sum(getsiginrange(gene, GeneRange(TSS(), TES(), 0, 0), ind)) for ind in atac_inds]) > 0
   
    end
end 

CSV.write("./data/low_ds_df.csv", low_ds_df)