import decimal
from collections import namedtuple
from decimal import Decimal, getcontext
from statistics import median

import pandas
from scipy.stats import mannwhitneyu
from util import constants


JudgementResult = namedtuple('JudgementResult', ('group', 'passed', 'failure_reason', 'p_value',
                                                 'sample_size', 'tested_size'))

getcontext().prec = 20


class ActionTolerance(dict):
	def __init__(self, action_tolerances):
		super().__init__(action_tolerances)
	
	def get_tolerance_range(self, action):
		tolerance = self.get(action)
		if not tolerance:
			return None
		return Decimal(tolerance)

	def set_tolerance_range(self, action, tolerance):
		setattr(self, action, tolerance)


class SampleObject:
	def __init__(self, values, cast_type='float64'):
		pandas.set_option("precision", 20)
		self.values = values.astype(cast_type)
	
	def shift(self, shift_value):
		self.values = self.values.add(pandas.to_numeric(shift_value, downcast='float'))  # use Decimal in the case of precision lack

	def median(self):
		return median(self.values)


def find_required_tolerance(p_value, ):
	pass


def judge_results_by_mannwhitney(base_sample, tested_sample, tolerance=Decimal(0.03)):
	baseline_sample = SampleObject(base_sample)
	# First we shift tested sample a little bit back likely closer to baseline.
	# This will be acceptance ratio: if tested one is slower less or equal than 3% - we do accept this
	
	mu = - tolerance * Decimal(base_sample.median())
	
	tested_shifted_sample = SampleObject(tested_sample)
	tested_shifted_sample.shift(mu)

	# TODO: 2/ check the hypothesis in comments of question
	# TODO: https://stats.stackexchange.com/questions/439611/am-i-doing-it-right-conducting-mann-whitney-test-in-scipy
	# TODO: play with mannwhitney, or wilcoxon signed rank test
	pvalue_sided_less = 0

	u_statistic_less, pvalue_sided_less = mannwhitneyu(
		baseline_sample.values,
		tested_shifted_sample.values,
		alternative='less', use_continuity=False)

	mw_alpha = Decimal(0.05)  # critical value for mann whitney test (significance level)
	
	# NOTE: if p_value less than critical value,
	# then algorithm can reject hypothesis 'tested result is slower than baseline'
	# in opposite, if p_value is more or equal, there is not enough evidence to reject tested
	hypothesis_rejected = pvalue_sided_less < mw_alpha
	test_passed = not hypothesis_rejected
	return test_passed, pvalue_sided_less
	
	
def judge(dataframe_baseline: pandas.DataFrame, dataframe_tested: pandas.DataFrame, measurement_by_column='elapsed'):
	# TODO: get tolerance from config for every of actions
	# TODO: once having different stages of judging , separate it by stages. Now it is just one stage
	judgement_results = []
	tolerances = ActionTolerance(action_tolerances=constants.CPT_CONFLUENCE_TOLERANCES)
	new_tolerances = {}

	for group in dataframe_baseline.groups:
		tolerance = tolerances.get_tolerance_range(action=group)
		if not tolerance:
			print(f"Warning: no tolerance for group {group}")
			continue

		print("group ", group)
		sample_base = dataframe_baseline.get_group(group)[measurement_by_column]
		sample_tested = dataframe_tested.get_group(group)[measurement_by_column]
		p_value = 0  # 1
		# while p_value < 0.05: # float(p_value) - 0.01 > 0.05
		
		try:
			test_passed, p_value = judge_results_by_mannwhitney(
				sample_base,
				sample_tested,
				tolerance=tolerance)
			# print(f"p value now is {p_value}")
			# if p_value < 0.05:
			# 	tolerance += round(decimal.Decimal(0.01), 2)
			#
			# elif p_value >= 0.05:
			# 	new_tolerances[group] = float(tolerance)
			# elif p_value + float(round(decimal.Decimal(0.01), 2)) >= 0.05:
			# 	tolerance += round(decimal.Decimal(0.01), 2)
			# 	new_tolerances[group] = float(tolerance)
			# 	break
			# elif p_value - 0.05 <= 0.01:
			# 	new_tolerances[group] = float(tolerance)
			# 	break
			# if tolerance - decimal.Decimal(0.01) < 0.01:
			# 	new_tolerances[group] = float(tolerance)
			# 	break
			# tolerance -= decimal.Decimal(0.01)
			# TODO: later we may define many failure reasons
			failure_reason = 'Results deviation is not accepted' if not test_passed else None
			judgement_results.append(
				JudgementResult(
					group=group, passed=test_passed,
					failure_reason=failure_reason, p_value=p_value, sample_size=len(sample_base), tested_size=len(sample_tested))
			)
		except decimal.InvalidOperation as e:
			judgement_results.append(JudgementResult(
				group=group, passed=False, p_value=None,
				sample_size=len(sample_base), tested_size=len(sample_tested),
				failure_reason=f'Failed to evaluate results by Mann Whitney: Error: {e}.'
				f'Check results for this group.')
			)
			# break
		# print(f"found tolerance for {group}: {tolerance}")
		# print(f'found for {count}th action')
		# new_tolerances[group] = float(tolerance)
		print(new_tolerances)
	return judgement_results
