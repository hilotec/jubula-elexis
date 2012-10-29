package com.hilotec.jubula.stringfunctions;

import org.eclipse.jubula.client.core.functions.AbstractFunctionEvaluator;
import org.eclipse.jubula.tools.exception.InvalidDataException;

public class Strpos2Evaluator extends AbstractFunctionEvaluator {

	@Override
	public String evaluate(String[] arguments) throws InvalidDataException {
		validateParamCount(arguments, 2);
		int begin = Integer.parseInt(arguments[1]);
		return arguments[0].substring(begin);
	}

}

