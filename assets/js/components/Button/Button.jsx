import React from 'react';
import classNames from 'classnames';

const getSizeClasses = (size) => {
  switch (size) {
    case 'small':
      return 'py-1 px-2 text-sm';
    default:
      return 'py-2 px-4 text-base';
  }
};

const getButtonClasses = (type) => {
  switch (type) {
    case 'primary-white':
      return 'bg-white hover:opacity-75 focus:outline-none text-jungle-green-500 w-full transition ease-in duration-200 text-center font-semibold rounded shadow';
    case 'primary-white-fit':
      return 'bg-white hover:opacity-75 focus:outline-none text-jungle-green-500 w-fit transition ease-in duration-200 text-center font-semibold rounded shadow';
    case 'transparent':
      return 'bg-transparent hover:opacity-75 focus:outline-none w-full transition ease-in duration-200 font-semibold';
    case 'secondary':
      return 'bg-persimmon hover:opacity-75 focus:outline-none text-gray-800 w-full transition ease-in duration-200 text-center font-semibold rounded shadow';
    case 'default-fit':
      return 'bg-jungle-green-500 hover:opacity-75 focus:outline-none text-white w-fit transition ease-in duration-200 text-center font-semibold rounded shadow';
    default:
      return 'bg-jungle-green-500 hover:opacity-75 focus:outline-none text-white w-full transition ease-in duration-200 text-center font-semibold rounded shadow';
  }
};

function Button({ children, className, type, size, ...props }) {
  const buttonClasses = classNames(
    getButtonClasses(type),
    getSizeClasses(size),
    className
  );
  return (
    <button type="button" className={buttonClasses} {...props}>
      {children}
    </button>
  );
}

export default Button;
