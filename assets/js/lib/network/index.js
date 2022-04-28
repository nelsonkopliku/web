import axios from 'axios';
import { logError, logWarn } from '@lib/log';

const conf = {
  validateStatus: (status) => {
    return status < 500;
  },
};

export const axiosPost = function (url, data) {
  return new Promise((resolve, reject) => {
    axios
      .post(url, data, conf)
      .then((response) => {
        handleResponseStatus(response);
        resolve(response);
      })
      .catch((error) => {
        logError(error);
        reject(error);
      });
  });
};

export const axiosDelete = function (url) {
  return new Promise((resolve, reject) => {
    axios
      .delete(url, conf)
      .then((response) => {
        handleResponseStatus(response);
        resolve(response);
      })
      .catch((error) => {
        logError(error);
        reject(error);
      });
  });
};

export const axiosPut = function (url, data) {
  return new Promise((resolve, reject) => {
    axios
      .put(url, data, conf)
      .then((response) => {
        handleResponseStatus(response);
        resolve(response);
      })
      .catch((error) => {
        logError(error);
        reject(error);
      });
  });
};

export const axiosGet = function (url) {
  return new Promise((resolve, reject) => {
    axios
      .get(url, conf)
      .then((response) => {
        handleResponseStatus(response);
        resolve(response);
      })
      .catch((error) => {
        logError(error);
        reject(error);
      });
  });
};

function handleResponseStatus(response) {
  if (response.status < 400) {
    return response;
  }
  switch (response.status) {
    case 401:
    case 403:
      logWarn('Redirecting to login after status', response.status);
      window.location.href = '/session/new';
      break;

    default:
      logError(response.statusText);
  }

  return response;
}
