var $BACK_ERR = function (error) {
    var target = typeof window !== 'undefined' ? window : global;
    if (target.onError)
        return target.onError(error);
    else
        throw error;
};
(function () {
    var exist, fs, readme, readme2, test;
    fs = require('fs');
    test = function ($BACK) {
        var exist;
        return fs.exists('../readme.md', function (error, exist) {
            if (error)
                return $BACK ? $BACK(error) : $BACK_ERR(error);
            return fs.exists('../readme.md', function (error, exist) {
                if (error)
                    return $BACK ? $BACK(error) : $BACK_ERR(error);
                return $BACK ? $BACK(null, exist) : exist;
            });
        });
    };
    return fs.exists('../readme.md', function (error, exist) {
        if (error)
            return $BACK ? $BACK(error) : $BACK_ERR(error);
        if (exist) {
            return fs.readFile('../readme.md', function (error, readme) {
                if (error)
                    return $BACK ? $BACK(error) : $BACK_ERR(error);
                console.log(readme);
            });
        }
        return fs.readFile('../readme.md', function (error, readme2) {
            readme2 = {
                error: error,
                value: readme2
            };
            console.dir(readme2);
        });
    });
}.call(this));