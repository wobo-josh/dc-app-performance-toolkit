from itertools import permutations
import sys

from prettytable import PrettyTable

from judgement import judge
from util.data_preparation.dataframe_converter import files_to_dataframe


def group_data_by_label(dataframe, columns=('label', )):
    """
    Transform jtl file to csv with groupped data by given fields
    :param input_file: input file in csv format
    :param columns: fields to group by
    :return:
    """
    return dataframe.groupby(list(columns))


def analyze_measured_results(baseline_result_filepath, experiment_result_filepath):
    raw_dataframe_baseline = files_to_dataframe(baseline_result_filepath)
    raw_dataframe_experiment = files_to_dataframe(experiment_result_filepath)
    
    df_baseline = group_data_by_label(raw_dataframe_baseline, columns=('label', ))
    df_tested = group_data_by_label(raw_dataframe_experiment, columns=('label', ))
    judgement_results = judge(df_baseline, df_tested, measurement_by_column='elapsed')
    table = PrettyTable(["Group", "Test result / regression not occurred", "p_value", 'sample_size', 'tested_size'])

    for judgement_result in judgement_results:
        if not judgement_result.passed:
            print(f"ERROR: Tested version is bigger for action {judgement_result.group}."
                  f"{baseline_result_filepath}-{experiment_result_filepath}")
        table.add_row([judgement_result.group, judgement_result.passed, judgement_result.p_value,
                       judgement_result.sample_size, judgement_result.tested_size])

    # if any(not judgement_result.passed for judgement_result in judgement_results):
    #     raise Exception("Tests has failed because some .")

    print(table)


if __name__ == '__main__':
    arguments = sys.argv[1:]
    analyze_measured_results(*arguments)
